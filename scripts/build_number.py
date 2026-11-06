#!/usr/bin/env python3
"""Persistent, atomic build-number allocator for Valora release candidates.

One source of truth: a state file holding the last allocated CFBundleVersion.

Rules (V0097):
  * Only the packaging step allocates, so one delivery = one increment.
    `build.sh` forwards to `package.py`, which allocates exactly once.
  * Allocation is exclusive across processes (`fcntl.flock`), and the write is
    atomic (temp file + rename) so a crash cannot hand out the same number twice.
  * A failed write leaves the counter untouched: no false success, and a skipped
    number is acceptable — reusing an allocated number is not.
  * Debug/test builds never call this script.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_STATE_DIR = Path.home() / "Library" / "Application Support" / "Valora"
STATE_NAME = "build-number.json"
LOCK_NAME = "build-number.lock"


def state_path(state_dir: Path) -> Path:
    return state_dir / STATE_NAME


def read_last(state_dir: Path) -> int:
    path = state_path(state_dir)
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return 0
    except (json.JSONDecodeError, OSError) as error:
        raise SystemExit(f"unreadable build-number state: {path}: {error}")
    if not isinstance(data, dict):
        raise SystemExit(f"invalid build-number state (not an object): {path}")
    value = data.get("last")
    # bool is an int subclass: a `true` counter would silently allocate 2.
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise SystemExit(f"invalid build-number state: {path}")
    return value


def write_last(state_dir: Path, value: int) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    payload = json.dumps({"last": value, "updated": __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc).isoformat()}, sort_keys=True) + "\n"
    fd, tmp = tempfile.mkstemp(dir=str(state_dir), prefix=".build-number.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, state_path(state_dir))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def allocate(state_dir: Path) -> int:
    """Return the next build number and persist it, atomically and exclusively."""
    state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = state_dir / LOCK_NAME
    with open(lock_path, "w") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            next_value = read_last(state_dir) + 1
            write_last(state_dir, next_value)
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    return next_value


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Allocate Valora build numbers")
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE_DIR,
                        help="directory holding the counter (tests use a temp dir)")
    parser.add_argument("--peek", action="store_true", help="print the last allocated number")
    args = parser.parse_args(argv)
    if args.peek:
        print(read_last(args.state_dir))
        return 0
    print(allocate(args.state_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
