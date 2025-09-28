import asyncio
import pytest

from maestro_tui.tools import run_shell_command


@pytest.mark.asyncio
async def test_run_shell_command_echo():
    out = await run_shell_command(["bash", "-lc", "echo -n hi"])
    assert out.exit_code == 0 and out.output == "hi"


@pytest.mark.asyncio
async def test_run_shell_command_timeout():
    out = await run_shell_command(["bash", "-lc", "sleep 1"], timeout=0.1)
    assert out.exit_code == 124 and out.stderr == "timeout"

