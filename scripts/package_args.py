#!/usr/bin/env python3
"""Argument + build-number entry for the real packaging step.

The build number is *always* allocated by `scripts/build_number.py`; there is no
manual override, because `--build` could hand out an older or duplicated number.
One packaging run allocates exactly once. Copying an already packaged app does
not go through this module, so it cannot consume a number.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOCATOR = Path(__file__).resolve().parent / "build_number.py"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Package the Valora release candidate")
    parser.add_argument("--binary", required=True, type=Path,
                        help="Binary produced by the current release build")
    parser.add_argument("--version", default="1.0.2")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    parser.add_argument("--lock-diagnostic-path", default=None,
                        help="Optional LSEnvironment diagnostic path for a QA candidate")
    return parser


def allocate(state_dir: Path | None = None) -> str:
    command = [sys.executable, str(ALLOCATOR)]
    if state_dir is not None:
        command += ["--state-dir", str(state_dir)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("build number allocation failed: " + (result.stderr or result.stdout))
    value = result.stdout.strip()
    if not value.isdigit():
        raise SystemExit("build number allocation returned an invalid value: " + value)
    return value


def parse(argv: list[str]) -> argparse.Namespace:
    parser = build_parser()
    for argument in argv:
        if argument == "--build" or argument.startswith("--build="):
            parser.error("--build is not supported: the build number is allocated "
                         "automatically and must increase monotonically")
    return parser.parse_args(argv)


def resolve(argv: list[str], state_dir: Path | None = None) -> tuple[argparse.Namespace, str]:
    """Parse the real packaging arguments and allocate exactly one number."""
    args = parse(argv)
    return args, allocate(state_dir)


if __name__ == "__main__":
    parsed, number = resolve(sys.argv[1:])
    print(number)
