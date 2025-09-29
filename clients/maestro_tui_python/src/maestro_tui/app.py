from __future__ import annotations

import asyncio
import signal
import time
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Static, Input, ListView, ListItem, Button
from textual.widgets.scroll_view import ScrollView
from textual.containers import Horizontal, Vertical
from rich.markdown import Markdown as RichMarkdown
from textual.screen import Screen
from textual import on

from .config import load_config
from .api.client import MaestroAPI
from .sse import drain_until_final
from .orchestrator import send_and_orchestrate


class MaestroTextual(App):
    BINDINGS = [
        ("ctrl+shift+n", "new_session", "New Session"),
        ("ctrl+shift+t", "threads", "Threads"),
        ("ctrl+shift+h", "help", "Help"),
    ]
    CSS = """
    Screen { align: center middle; }
    #status { height: 1; }
    #sessions { width: 40; }
    #chat_scroll { width: 80; height: 40; }
    """

    def __init__(self) -> None:
        super().__init__()
        self.api: MaestroAPI | None = None
        self.sessions: list[dict] = []
        self.current_session_id: str | None = None
        self.current_thread_id: str | None = None
        self._session_meta: dict[str, dict] = {}
        self._selected_provider: str | None = None
        self._quit_armed: bool = False
        self._quit_armed_at: float = 0.0

    async def on_mount(self) -> None:
        cfg = load_config()
        self.api = MaestroAPI(cfg)
        await self.refresh_sessions()
        self._install_sigint_double_tap()

    async def on_unmount(self) -> None:
        if self.api:
            await self.api.close()

    def _install_sigint_double_tap(self) -> None:
        def handler(signum, frame):  # noqa: ARG001
            def do():
                now = time.time()
                if (not self._quit_armed) or (now - self._quit_armed_at > 3.0):
                    self._quit_armed = True
                    self._quit_armed_at = now
                    try:
                        self.query_one("#status", Static).update("Press Ctrl+C again to quit")
                    except Exception:
                        pass
                else:
                    self.exit()

            try:
                self.call_from_thread(do)
            except Exception:
                # last resort
                self.exit()

        try:
            signal.signal(signal.SIGINT, handler)
        except Exception:
            pass

    async def refresh_sessions(self) -> None:
        assert self.api
        self.sessions = await self.api.list_remote_sessions()
        lv = self.query_one("#sessions", ListView)
        lv.clear()
        for s in self.sessions:
            lv.append(ListItem(Static(f"{s.get('name') or s['id']}", expand=True)))
            sid = str(s["id"])
            self._session_meta[sid] = {
                "working_dir": s.get("working_dir")
            }

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            with Vertical(id="left"):
                yield Button("➕ New Session", id="btn-new")
                yield Button("🧵 Threads", id="btn-threads")
                yield ListView(id="sessions")
            with ScrollView(id="chat_scroll"):
                yield Static("", id="chat")
        yield Input(placeholder="Type message...", id="composer")
        yield Static("Ready", id="status")
        yield Footer()

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.index
        if 0 <= idx < len(self.sessions):
            self.current_session_id = self.sessions[idx]["id"]
            await self._load_latest_thread_and_transcript()
            self.query_one("#status", Static).update(f"Selected {self.current_session_id}")

    async def on_input_submitted(self, event: Input.Submitted) -> None:
        text = event.value or ""
        stripped = text.strip()
        if stripped == "":
            self.query_one("#status", Static).update("Type a message or a /command")
            return
        try:
            event.input.value = ""
            event.input.refresh()
        except Exception:
            pass
        if stripped.startswith("/"):
            handled = await self.handle_slash_command(stripped)
            if handled:
                return
        if not self.current_session_id:
            self.query_one("#status", Static).update("Pick a remote session first")
            return
        assert self.api
        prov = (self._session_meta.get(self.current_session_id, {}) or {}).get("provider") or self._selected_provider or ""
        base_dir = (self._session_meta.get(self.current_session_id, {}) or {}).get("working_dir") or "."
        async def _send():
            try:
                msgs = await send_and_orchestrate(
                    self.api,
                    session_id=self.current_session_id,
                    message=stripped,
                    provider=prov,
                    base_dir=base_dir,
                )
                if self.current_thread_id:
                    await self._load_latest_thread_and_transcript()
                else:
                    await self._append_messages(msgs)
                self.query_one("#status", Static).update("Sent")
            except Exception as e:
                self.query_one("#status", Static).update(f"Error: {e}")
        asyncio.create_task(_send())

    async def handle_slash_command(self, text: str) -> bool:
        assert self.api
        cmdline = text.lstrip("/").strip()
        if not cmdline:
            return False
        name, *rest = cmdline.split()
        name = name.lower()
        if name in ("help", "h"):
            self.query_one("#status", Static).update("/help /model /clear /threads")
            return True
        if name in ("model", "session"):
            self.open_wizard()
            return True
        if name in ("threads", "thread"):
            await self.open_threads()
            return True
        if name == "clear":
            if not self.current_thread_id:
                self.query_one("#status", Static).update("No thread selected")
                return True
            await self.api.clear_thread(self.current_thread_id)
            self._transcript = []
            self.query_one("#chat", Static).update("")
            self.query_one("#status", Static).update("Thread cleared")
            return True
        return False

    async def _load_latest_thread_and_transcript(self) -> None:
        assert self.api and self.current_session_id
        threads = await self.api.list_threads(self.current_session_id)
        if not threads:
            self.current_thread_id = None
            self.query_one("#chat", Static).update("")
            return
        threads.sort(key=lambda t: t.get("updated_at") or "", reverse=True)
        await self.set_current_thread(threads[0]["id"])

    async def _append_messages(self, new_msgs: list[dict]) -> None:
        cur = getattr(self, "_transcript", [])
        cur.extend(new_msgs)
        self._transcript = cur
        await self._render_transcript(cur)

    async def _render_transcript(self, messages: list[dict]) -> None:
        normalized: list[dict] = []
        for m in messages:
            role = m.get("role")
            text = m.get("text")
            if text is None:
                parts = m.get("content") or []
                text = "".join(p.get("text", "") for p in parts if p.get("type") == "text")
            normalized.append({"role": role, "text": text})
        self._transcript = normalized
        md = self._build_markdown(normalized)
        self.query_one("#chat", Static).update(RichMarkdown(md))
        try:
            self.query_one("#chat_scroll", ScrollView).scroll_end(animate=False)
        except Exception:
            pass

    def _build_markdown(self, messages: list[dict]) -> str:
        out: list[str] = []
        for m in messages:
            role = (m.get("role") or "").lower()
            text = m.get("text") or ""
            if role == "user":
                out.append(f"**You**\n\n{text}\n\n---\n")
            elif role == "assistant":
                out.append(f"**Assistant**\n\n{text}\n\n---\n")
            elif role == "tool":
                out.append(f"**Tool**\n\n```\n{text}\n```\n\n---\n")
            elif role == "system":
                out.append(f"**System**\n\n{text}\n\n---\n")
        return "".join(out)

    async def set_current_thread(self, thread_id: str) -> None:
        assert self.api
        self.current_thread_id = thread_id
        messages = await self.api.thread_snapshot(thread_id)
        await self._render_transcript(messages)

    @on(Button.Pressed, "#btn-new")
    def open_wizard(self) -> None:
        self.push_screen(NewSessionWizard(self.api, self._on_session_created))

    @on(Button.Pressed, "#btn-threads")
    async def open_threads(self) -> None:
        if not self.current_session_id:
            self.query_one("#status", Static).update("Pick a session first")
            return
        self.push_screen(ThreadPicker(self.api, self.current_session_id, self._on_thread_selected))

    def action_new_session(self) -> None:
        self.open_wizard()

    def action_threads(self) -> None:
        self.call_from_executor(asyncio.create_task, self.open_threads())

    def action_help(self) -> None:
        self.query_one("#status", Static).update("Hotkeys: Ctrl+Shift+N new, Ctrl+Shift+T threads. Slash: /help /model /threads /clear")

    async def _on_session_created(self, session_id: str) -> None:
        await self.refresh_sessions()
        # Select the newly created session
        for i, s in enumerate(self.sessions):
            if s["id"] == session_id:
                self.query_one("#sessions", ListView).index = i
                self.current_session_id = session_id
                if self._selected_provider:
                    meta = self._session_meta.get(session_id, {}) or {}
                    meta["provider"] = self._selected_provider
                    self._session_meta[session_id] = meta
                await self._load_latest_thread_and_transcript()
                break


class NewSessionWizard(Screen):
    BINDINGS = [
        ("escape", "app.pop_screen", "Close"),
    ]

    def __init__(self, api: MaestroAPI | None, on_created_cb):
        super().__init__()
        self.api = api
        self.on_created_cb = on_created_cb
        self.providers: list[str] = []
        self.auths: list[dict] = []
        self.models: list[str] = []
        self.selected_provider: str | None = None
        self.selected_auth: str | None = None
        self.selected_model: str | None = None

    async def on_mount(self) -> None:
        assert self.api
        self.providers = await self.api.list_providers()
        lv = self.query_one("#providers", ListView)
        for p in self.providers:
            lv.append(ListItem(Static(p)))

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        with Horizontal():
            yield ListView(id="providers")
            yield ListView(id="auths")
            yield ListView(id="models")
        yield Button("Create Session", id="btn-create", disabled=True)
        yield Footer()

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        assert self.api
        wid = event.list_view.id
        if wid == "providers":
            self.selected_provider = self.providers[event.index]
            # Load auths
            self.auths = await self.api.list_saved_auths(self.selected_provider)
            la = self.query_one("#auths", ListView)
            la.clear()
            for a in self.auths:
                la.append(ListItem(Static(f"{a['label']} ({a['id']})")))
            # Clear models
            self.query_one("#models", ListView).clear()
            self.selected_auth = None
            self.selected_model = None
        elif wid == "auths":
            if not self.selected_provider:
                return
            self.selected_auth = self.auths[event.index]["id"]
            models = await self.api.list_models(self.selected_provider, self.selected_auth)
            self.models = models
            lm = self.query_one("#models", ListView)
            lm.clear()
            for m in models:
                lm.append(ListItem(Static(m)))
            self.selected_model = None
        elif wid == "models":
            self.selected_model = self.models[event.index]
        self._update_create_button()

    @on(Button.Pressed, "#btn-create")
    async def create_session(self) -> None:
        assert self.api and self.selected_auth and self.selected_model
        # remember provider on the app for orchestration
        try:
            self.app._selected_provider = self.selected_provider
        except Exception:
            pass
        session_id = await self.api.create_session(
            auth_id=self.selected_auth,
            model=self.selected_model,
            tool_runtime="remote",
        )
        await self.on_created_cb(session_id)
        self.app.pop_screen()

    def _update_create_button(self) -> None:
        btn = self.query_one("#btn-create", Button)
        btn.disabled = not (self.selected_provider and self.selected_auth and self.selected_model)


class ThreadPicker(Screen):
    BINDINGS = [("escape", "app.pop_screen", "Close")]

    def __init__(self, api: MaestroAPI | None, session_id: str, on_selected_cb):
        super().__init__()
        self.api = api
        self.session_id = session_id
        self.on_selected_cb = on_selected_cb
        self.threads: list[dict] = []

    async def on_mount(self) -> None:
        assert self.api
        self.threads = await self.api.list_threads(self.session_id)
        self.threads.sort(key=lambda t: t.get("updated_at") or "", reverse=True)
        lv = self.query_one("#threads", ListView)
        for t in self.threads:
            label = t.get("label") or t.get("id")
            lv.append(ListItem(Static(label)))

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield ListView(id="threads")
        yield Footer()

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.index
        if 0 <= idx < len(self.threads):
            tid = self.threads[idx]["id"]
            await self.on_selected_cb(tid)
            self.app.pop_screen()


def main() -> None:
    MaestroTextual().run()


if __name__ == "__main__":
    main()
