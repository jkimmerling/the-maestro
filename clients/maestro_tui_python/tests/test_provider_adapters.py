import asyncio
from pathlib import Path

import pytest

from maestro_tui.providers.adapters import normalize, execute_normalized


@pytest.mark.asyncio
async def test_gemini_run_shell_command_normalization_and_exec(tmp_path: Path):
    tool, na = normalize("gemini", "run_shell_command", {"command": "echo hi", "directory": str(tmp_path)})
    assert tool == "run_shell_command"
    assert na["command"] == ["bash", "-lc", "echo hi"]
    out = await execute_normalized(tool, na, str(tmp_path))
    assert '"exit_code": 0' in out and '"output": "hi' in out


def test_anthropic_titlecase_mappings():
    tool, na = normalize("anthropic", "Grep", {"pattern": "foo", "paths": ["a.txt"]})
    assert tool == "grep" and na["pattern"] == "foo"


def test_openai_shell_normalization():
    tool, na = normalize("openai", "shell", {"command": ["bash", "-lc", "echo"], "timeout_ms": 5000})
    assert tool == "shell" and na["timeout"] == 5.0

