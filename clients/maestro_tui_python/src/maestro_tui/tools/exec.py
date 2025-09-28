from __future__ import annotations

import asyncio
import shlex
import time
from dataclasses import dataclass
from typing import List, Optional
from pathlib import Path


@dataclass
class ExecOutput:
    output: str
    stderr: str
    exit_code: int
    duration_seconds: float


async def run_shell_command(args: List[str] | str, cwd: Optional[str | Path] = None, timeout: Optional[float] = None) -> ExecOutput:
    if isinstance(args, str):
        cmd = shlex.split(args)
    else:
        cmd = list(args)
    if not cmd:
        raise ValueError("empty command")
    start = time.monotonic()
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        cwd=str(cwd) if cwd else None,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        out_b, err_b = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        duration = time.monotonic() - start
        return ExecOutput(output="", stderr="timeout", exit_code=124, duration_seconds=duration)
    duration = time.monotonic() - start
    return ExecOutput(output=out_b.decode(), stderr=err_b.decode(), exit_code=proc.returncode or 0, duration_seconds=duration)

