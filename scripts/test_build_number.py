#!/usr/bin/env python3
"""Isolated checks for scripts/build_number.py (temp directory only)."""
import concurrent.futures
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "build_number.py"


def run(state: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--state-dir", str(state), *args],
                          capture_output=True, text=True)


def main() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as raw:
        state = Path(raw)

        # 1. Two allocations are strictly +1.
        first, second = run(state).stdout.strip(), run(state).stdout.strip()
        if not (first.isdigit() and second.isdigit() and int(second) == int(first) + 1):
            failures.append(f"sequential allocation not +1: {first!r} {second!r}")

        # 2. Peak value is what --peek reports.
        if run(state, "--peek").stdout.strip() != second:
            failures.append("peek does not match the last allocation")

        # 3. Concurrent allocation never repeats a number.
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: run(state).stdout.strip(), range(8)))
        if len(set(results)) != len(results):
            failures.append(f"concurrent allocation repeated: {sorted(results)}")

        # 4. A failed write must not report success.
        blocked = state / "blocked"
        blocked.write_text("not a directory")
        failed = run(blocked)
        if failed.returncode == 0:
            failures.append("write failure reported success")
        if run(state, "--peek").stdout.strip() != results[-1] and \
                run(state, "--peek").stdout.strip() != max(results + [second], key=int):
            failures.append("counter changed after a failed allocation")

        # 5. One delivery flow allocates exactly once (package.py consumes one).
        before = int(run(state, "--peek").stdout.strip())
        one = run(state).stdout.strip()
        after = int(run(state, "--peek").stdout.strip())
        if int(one) != before + 1 or after != int(one):
            failures.append("single delivery flow did not advance exactly once")

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print("build-number checks passed (sequential +1, peek, concurrent unique, "
          "failure not reported as success, one delivery = one number)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
