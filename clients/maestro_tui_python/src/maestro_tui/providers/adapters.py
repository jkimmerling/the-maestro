from __future__ import annotations

from typing import Any, Dict, Tuple

from ..tools import run_shell_command, write_file, edit_file, multi_edit, list_directory, glob_paths, grep, read_file
from ..tools.exec import ExecOutput, exec_output_json


def normalize(provider: str, name: str, args: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    p = provider.lower()
    n = name

    if p == "openai":
        if n == "shell":
            cmd = args.get("command")
            workdir = args.get("workdir")
            timeout_ms = args.get("timeout_ms")
            if isinstance(cmd, list):
                normalized = {"command": cmd, "cwd": workdir, "timeout": (float(timeout_ms) / 1000.0) if timeout_ms else None}
            else:
                normalized = {"command": cmd, "cwd": workdir, "timeout": (float(timeout_ms) / 1000.0) if timeout_ms else None}
            return ("shell", normalized)
        if n == "apply_patch":
            return ("apply_patch", {"input": args.get("input")})
        if n == "web_search":
            return ("web_search", args)
        if n == "update_plan":
            return ("todo_write", {"todos": args.get("plan", [])})
        if n == "view_image":
            return ("view_image", {"path": args.get("path")})

    if p == "gemini":
        if n == "run_shell_command":
            cmd = args.get("command")
            directory = args.get("directory")
            return ("run_shell_command", {"command": ["bash", "-lc", cmd], "cwd": directory})
        if n == "list_directory":
            return ("list_directory", {"path": args.get("path")})
        if n == "glob":
            return ("glob", {"pattern": args.get("pattern"), "path": args.get("path")})
        if n in ("search_file_content", "grep"):
            return ("grep", {"pattern": args.get("pattern"), "files": args.get("files")})
        if n in ("replace", "edit"):
            return ("edit_file", {"path": args.get("file_path"), "find": args.get("find"), "replace": args.get("replace"), "count": args.get("expected_replacements")})
        if n == "read_many_files":
            return ("read_many", {"paths": args.get("paths", [])})
        if n == "web_fetch":
            return ("web_fetch", {"url": args.get("url")})
        if n == "google_web_search":
            return ("web_search", {"query": args.get("query"), "backend": "google"})

    if p == "anthropic":
        # TitleCase mapping
        title = n
        m = {
            "Bash": ("run_shell_command", {"command": ["bash", "-lc", args.get("command")], "cwd": args.get("workdir")}),
            "Read": ("read_file", {"path": args.get("path")}),
            "Write": ("write_file", {"file_path": args.get("file_path"), "content": args.get("content")}),
            "Edit": ("edit_file", {"path": args.get("path"), "find": args.get("find"), "replace": args.get("replace")}),
            "MultiEdit": ("multi_edit", {"ops": args.get("ops", [])}),
            "NotebookEdit": ("notebook_edit", args),
            "Glob": ("glob", {"pattern": args.get("pattern")}),
            "Grep": ("grep", {"pattern": args.get("pattern"), "files": args.get("paths")}),
            "WebFetch": ("web_fetch", {"url": args.get("url")}),
            "WebSearch": ("web_search", {"query": args.get("query")}),
            "TodoWrite": ("todo_write", {"todos": args.get("todos", [])}),
        }
        if title in m:
            return m[title]

    return (n, args)


async def execute_normalized(tool: str, args: Dict[str, Any], base_dir: str) -> str:
    if tool in ("shell", "run_shell_command"):
        cmd = args.get("command")
        cwd = args.get("cwd") or args.get("workdir")
        timeout = args.get("timeout")
        out: ExecOutput = await run_shell_command(cmd, cwd, timeout)
        return exec_output_json(out)
    if tool == "write_file":
        p = write_file(base_dir, args["file_path"], args.get("content", ""))
        return exec_output_json(ExecOutput(output=f"wrote: {p}", stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "edit_file":
        n = edit_file(base_dir, args["path"], args.get("find", ""), args.get("replace", ""), args.get("count"))
        return exec_output_json(ExecOutput(output=f"replacements: {n}", stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "multi_edit":
        res = multi_edit(base_dir, args.get("ops", []))
        return exec_output_json(ExecOutput(output=str(res), stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "list_directory":
        items = list_directory(base_dir, args.get("path", "."))
        return exec_output_json(ExecOutput(output="\n".join(items), stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "glob":
        items = glob_paths(base_dir, args.get("pattern", "*"))
        return exec_output_json(ExecOutput(output="\n".join(items), stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "grep":
        hits = grep(base_dir, args.get("pattern", "."), args.get("files"))
        out = "\n".join(f"{f}:{ln}:{line}" for f, ln, line in hits)
        return exec_output_json(ExecOutput(output=out, stderr="", exit_code=0, duration_seconds=0.0))
    if tool == "read_file":
        content = read_file(base_dir, args["path"])
        return exec_output_json(ExecOutput(output=content, stderr="", exit_code=0, duration_seconds=0.0))
    return exec_output_json(ExecOutput(output="unsupported tool", stderr="", exit_code=2, duration_seconds=0.0))

