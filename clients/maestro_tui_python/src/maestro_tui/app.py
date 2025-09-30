from __future__ import annotations

import asyncio
import signal
import time
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Static, Input, ListView, ListItem, Button
from textual.scroll_view import ScrollView
from textual.containers import Horizontal, Vertical
from rich.markdown import Markdown as RichMarkdown
from textual.screen import Screen
from textual import on, events

from .config import load_config, load_settings, save_settings, Settings
from .api.client import MaestroAPI
from .sse import drain_until_final
from .orchestrator import send_and_orchestrate


class ChatScreen(Screen):
    """Main chat interface"""

    BINDINGS = [
        ("ctrl+c", "double_quit", "Quit"),
    ]

    CSS = """
    ChatScreen { align: center middle; }
    #status { height: 1; }
    #chat_scroll { width: 100%; height: 1fr; }
    """

    def __init__(self) -> None:
        super().__init__()
        self._quit_armed: bool = False
        self._quit_armed_at: float = 0.0
        self._transcript: list[dict] = []

    def compose(self) -> ComposeResult:
        yield Header()
        with ScrollView(id="chat_scroll"):
            yield Static("", id="chat")
        yield Input(placeholder="Type message or /sessions, /model, /threads, /clear...", id="composer")
        yield Static("Ready", id="status")
        yield Footer()

    def action_double_quit(self) -> None:
        now = time.time()
        if (not self._quit_armed) or (now - self._quit_armed_at > 3.0):
            self._quit_armed = True
            self._quit_armed_at = now
            self.query_one("#status", Static).update("Press Ctrl+C again to quit")
        else:
            self.app.exit()

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

        # Handle slash commands
        if stripped.startswith("/"):
            await self.app.handle_slash_command(stripped, self)
            return

        # Lazy session creation
        if not self.app.current_session_id:
            settings = load_settings()
            if not settings.last_auth_id or not settings.last_model:
                self.query_one("#status", Static).update("No settings found. Use /model to configure.")
                return
            try:
                self.app.current_session_id = await self.app.api.create_session(
                    auth_id=settings.last_auth_id,
                    model=settings.last_model,
                    tool_runtime="remote"
                )
            except Exception as e:
                self.query_one("#status", Static).update(f"Failed to create session: {e}")
                return

        # Optimistic echo
        await self.append_messages([{"role": "user", "text": stripped}])

        assert self.app.api
        prov = self.app._selected_provider or ""
        base_dir = "."

        async def _send():
            try:
                msgs = await send_and_orchestrate(
                    self.app.api,
                    session_id=self.app.current_session_id,
                    message=stripped,
                    provider=prov,
                    base_dir=base_dir,
                )
                if self.app.current_thread_id:
                    await self.load_latest_thread_and_transcript()
                else:
                    await self.append_messages(msgs)
                self.query_one("#status", Static).update("Sent")
            except Exception as e:
                self.query_one("#status", Static).update(f"Error: {e}")

        asyncio.create_task(_send())

    async def load_latest_thread_and_transcript(self) -> None:
        assert self.app.api and self.app.current_session_id
        threads = await self.app.api.list_threads(self.app.current_session_id)
        if not threads:
            self.app.current_thread_id = None
            self.query_one("#chat", Static).update("")
            return
        threads.sort(key=lambda t: t.get("updated_at") or "", reverse=True)
        await self.set_current_thread(threads[0]["id"])

    async def set_current_thread(self, thread_id: str) -> None:
        assert self.app.api
        self.app.current_thread_id = thread_id
        messages = await self.app.api.thread_snapshot(thread_id)
        await self.render_transcript(messages)

    async def append_messages(self, new_msgs: list[dict]) -> None:
        self._transcript.extend(new_msgs)
        await self.render_transcript(self._transcript)

    async def render_transcript(self, messages: list[dict]) -> None:
        normalized: list[dict] = []
        for m in messages:
            role = m.get("role")
            text = m.get("text")
            if text is None:
                parts = m.get("content") or []
                text = "".join(p.get("text", "") for p in parts if p.get("type") == "text")
            normalized.append({"role": role, "text": text})
        self._transcript = normalized

        # Prune preamble before first user message and collapse duplicate assistant lines
        cut: list[dict] = []
        start = 0
        for i, mm in enumerate(normalized):
            if (mm.get("role") or "").lower() == "user":
                start = i
                break
        base = normalized[start:]
        prev: dict | None = None
        for mm in base:
            if (
                prev
                and (prev.get("role") or "").lower() == "assistant"
                and (mm.get("role") or "").lower() == "assistant"
                and (prev.get("text") or "") == (mm.get("text") or "")
            ):
                continue
            cut.append(mm)
            prev = mm
        self._transcript = cut
        md = self.build_markdown(cut)
        self.query_one("#chat", Static).update(RichMarkdown(md))
        try:
            self.query_one("#chat_scroll", ScrollView).scroll_end(animate=False)
        except Exception:
            pass

    def build_markdown(self, messages: list[dict]) -> str:
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

    async def on_mouse_scroll(self, event: events.MouseScroll) -> None:
        # Always scroll the transcript with mouse wheel
        try:
            sv = self.query_one("#chat_scroll", ScrollView)
            dy = getattr(event, "delta_y", 0) or 0
            if dy != 0:
                off = getattr(sv, "scroll_offset", None)
                if off is not None:
                    step = 4
                    new_y = max(0, off.y + (-dy) * step)
                    sv.scroll_to(y=new_y, animate=False)
                    event.stop()
                    return
                if dy > 0:
                    sv.scroll_to(y=0, animate=False)
                else:
                    sv.scroll_end(animate=False)
                event.stop()
        except Exception:
            pass


class SessionsScreen(Screen):
    """Sessions list and management"""

    BINDINGS = [("escape", "app.pop_screen", "Back")]

    CSS = """
    SessionsScreen { align: center middle; }
    #sessions { width: 60; height: 1fr; }
    """

    def __init__(self) -> None:
        super().__init__()
        self.sessions: list[dict] = []

    async def on_mount(self) -> None:
        await self.refresh_sessions()

    def compose(self) -> ComposeResult:
        yield Header()
        with Vertical():
            with Horizontal():
                yield Button("New Session", id="btn-new")
                yield Button("Delete Session", id="btn-delete")
                yield Button("Back to Chat", id="btn-back")
            yield ListView(id="sessions")
        yield Footer()

    async def refresh_sessions(self) -> None:
        assert self.app.api
        self.sessions = await self.app.api.list_remote_sessions()
        def ts(s: dict) -> str:
            return s.get("last_used_at") or s.get("updated_at") or s.get("inserted_at") or ""
        self.sessions.sort(key=ts, reverse=True)
        lv = self.query_one("#sessions", ListView)
        lv.clear()
        for s in self.sessions:
            lv.append(ListItem(Static(f"{s.get('name') or s['id']}", expand=True)))

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = event.index
        if 0 <= idx < len(self.sessions):
            self.app.current_session_id = self.sessions[idx]["id"]
            chat_screen = self.app.query_one(ChatScreen)
            await chat_screen.load_latest_thread_and_transcript()
            self.app.pop_screen()

    @on(Button.Pressed, "#btn-new")
    def open_new_session_wizard(self) -> None:
        self.app.push_screen(ModelPickerScreen(for_new_session=True))

    @on(Button.Pressed, "#btn-delete")
    async def delete_current_session(self) -> None:
        lv = self.query_one("#sessions", ListView)
        idx = lv.index
        if idx is None or idx < 0 or idx >= len(self.sessions):
            return
        session_id = self.sessions[idx]["id"]
        try:
            await self.app.api.delete_session(session_id)
            await self.refresh_sessions()
        except Exception as e:
            # Could show error in status bar
            pass

    @on(Button.Pressed, "#btn-back")
    def go_back(self) -> None:
        self.app.pop_screen()


class ModelPickerScreen(Screen):
    """Model picker for switching or creating sessions"""

    BINDINGS = [("escape", "app.pop_screen", "Back")]

    CSS = """
    ModelPickerScreen { align: center middle; }
    #providers, #auths, #models { width: 30; height: 1fr; }
    """

    def __init__(self, for_new_session: bool = False) -> None:
        super().__init__()
        self.for_new_session = for_new_session
        self.providers: list[str] = []
        self.auths: list[dict] = []
        self.models: list[str] = []
        self.selected_provider: str | None = None
        self.selected_auth_id: str | None = None
        self.selected_model: str | None = None

    async def on_mount(self) -> None:
        assert self.app.api
        self.providers = await self.app.api.list_providers()
        lv = self.query_one("#providers", ListView)
        for p in self.providers:
            lv.append(ListItem(Static(p)))

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            yield ListView(id="providers")
            yield ListView(id="auths")
            yield ListView(id="models")
        yield Button("Confirm", id="btn-confirm", disabled=True)
        yield Footer()

    async def on_list_view_selected(self, event: ListView.Selected) -> None:
        assert self.app.api
        wid = event.list_view.id
        if wid == "providers":
            self.selected_provider = self.providers[event.index]
            self.auths = await self.app.api.list_saved_auths(self.selected_provider)
            la = self.query_one("#auths", ListView)
            la.clear()
            for a in self.auths:
                la.append(ListItem(Static(f"{a['label']} ({a['id'][:8]}...)")))
            self.query_one("#models", ListView).clear()
            self.selected_auth_id = None
            self.selected_model = None
        elif wid == "auths":
            if not self.selected_provider:
                return
            self.selected_auth_id = self.auths[event.index]["id"]
            models = await self.app.api.list_models(self.selected_provider, self.selected_auth_id)
            self.models = models
            lm = self.query_one("#models", ListView)
            lm.clear()
            for m in models:
                lm.append(ListItem(Static(m)))
            self.selected_model = None
        elif wid == "models":
            self.selected_model = self.models[event.index]
        self._update_confirm_button()

    @on(Button.Pressed, "#btn-confirm")
    async def confirm_selection(self) -> None:
        if not (self.selected_auth_id and self.selected_model):
            return

        # Save to settings
        settings = Settings(
            last_provider=self.selected_provider,
            last_auth_id=self.selected_auth_id,
            last_model=self.selected_model,
        )
        save_settings(settings)
        self.app._selected_provider = self.selected_provider

        if self.for_new_session:
            # Create new session
            session_id = await self.app.api.create_session(
                auth_id=self.selected_auth_id,
                model=self.selected_model,
                tool_runtime="remote",
            )
            self.app.current_session_id = session_id
            chat_screen = self.app.query_one(ChatScreen)
            await chat_screen.load_latest_thread_and_transcript()
            # Pop back to sessions screen, then it will pop to chat
            self.app.pop_screen()
            self.app.pop_screen()
        else:
            # Update existing session if one is active
            if self.app.current_session_id:
                await self.app.api.update_session(
                    self.app.current_session_id,
                    auth_id=self.selected_auth_id,
                    model_id=self.selected_model,
                )
            self.app.pop_screen()

    def _update_confirm_button(self) -> None:
        btn = self.query_one("#btn-confirm", Button)
        btn.disabled = not (self.selected_provider and self.selected_auth_id and self.selected_model)


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


class MaestroTextual(App):
    """Main TUI application"""

    BINDINGS = [
        ("ctrl+shift+n", "new_session", "New Session"),
        ("ctrl+shift+t", "threads", "Threads"),
        ("ctrl+shift+h", "help", "Help"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.api: MaestroAPI | None = None
        self.current_session_id: str | None = None
        self.current_thread_id: str | None = None
        self._selected_provider: str | None = None

    async def on_mount(self) -> None:
        cfg = load_config()
        self.api = MaestroAPI(cfg)

        # Load settings
        settings = load_settings()
        self._selected_provider = settings.last_provider

        self._install_sigint_double_tap()
        self.push_screen(ChatScreen())

    async def on_unmount(self) -> None:
        if self.api:
            await self.api.close()

    def _install_sigint_double_tap(self) -> None:
        def handler(signum, frame):  # noqa: ARG001
            def do():
                try:
                    chat = self.query_one(ChatScreen)
                    chat.action_double_quit()
                except Exception:
                    self.exit()
            try:
                self.call_from_thread(do)
            except Exception:
                self.exit()
        try:
            signal.signal(signal.SIGINT, handler)
        except Exception:
            pass

    async def handle_slash_command(self, text: str, chat_screen: ChatScreen) -> None:
        cmdline = text.lstrip("/").strip()
        if not cmdline:
            return
        name, *rest = cmdline.split()
        name = name.lower()

        if name in ("help", "h"):
            chat_screen.query_one("#status", Static).update("/help /sessions /model /threads /clear")
            return

        if name in ("sessions", "session"):
            self.push_screen(SessionsScreen())
            return

        if name == "model":
            self.push_screen(ModelPickerScreen(for_new_session=False))
            return

        if name in ("threads", "thread"):
            if not self.current_session_id:
                chat_screen.query_one("#status", Static).update("No session selected")
                return
            self.push_screen(ThreadPicker(self.api, self.current_session_id, chat_screen.set_current_thread))
            return

        if name == "clear":
            if not self.current_thread_id:
                chat_screen.query_one("#status", Static).update("No thread selected")
                return
            await self.api.clear_thread(self.current_thread_id)
            chat_screen._transcript = []
            chat_screen.query_one("#chat", Static).update("")
            chat_screen.query_one("#status", Static).update("Thread cleared")
            return

    def action_new_session(self) -> None:
        self.push_screen(SessionsScreen())

    def action_threads(self) -> None:
        chat = self.query_one(ChatScreen)
        if not self.current_session_id:
            chat.query_one("#status", Static).update("No session selected")
            return
        self.push_screen(ThreadPicker(self.api, self.current_session_id, chat.set_current_thread))

    def action_help(self) -> None:
        try:
            chat = self.query_one(ChatScreen)
            chat.query_one("#status", Static).update("Hotkeys: Ctrl+Shift+N sessions, Ctrl+Shift+T threads. Slash: /help /sessions /model /threads /clear")
        except Exception:
            pass


def main() -> None:
    MaestroTextual().run()


if __name__ == "__main__":
    main()
