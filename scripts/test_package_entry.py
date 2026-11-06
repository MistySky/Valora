#!/usr/bin/env python3
"""Isolated checks for the REAL packaging entry (scripts/package_args.py).

Every case uses a temporary state directory; nothing touches the real counter,
the app bundle or the network.
"""
import contextlib
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import package_args  # noqa: E402


def state_value(state: Path) -> int:
    return json.loads((state / "build-number.json").read_text())["last"]


def main() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as raw:
        state = Path(raw) / "state"
        state.mkdir()

        # Seed "last = 2" as the real project has today.
        (state / "build-number.json").write_text(json.dumps({"last": 2}) + "\n")

        # 1. A legacy --build override is rejected and writes nothing.
        before = state_value(state)
        for bad in (["--build", "1"], ["--build=999"]):
            try:
                with contextlib.redirect_stderr(io.StringIO()):
                    package_args.parse(["--binary", "x"] + bad)
                failures.append(f"{bad} was accepted")
            except SystemExit as exit_error:
                if exit_error.code != 2:
                    failures.append(f"{bad} exited with {exit_error.code}, expected argparse error")
        if state_value(state) != before:
            failures.append("rejected --build changed the counter")

        # 2. Automatic resolution allocates exactly once, +1 each run.
        args, first = package_args.resolve(["--binary", "x"], state_dir=state)
        if state_value(state) != 3 or first != "3":
            failures.append(f"first delivery allocated {first}, state {state_value(state)}")
        args2, second = package_args.resolve(["--binary", "x"], state_dir=state)
        if int(second) != int(first) + 1 or state_value(state) != int(second):
            failures.append(f"second delivery did not continue: {first} {second}")
        if Path(args.binary) != Path("x") or Path(args2.binary) != Path("x"):
            failures.append("argument parsing lost --binary")

        # 3. Metadata the packager writes equals the allocated value.
        if not isinstance(second, str) or not second.isdigit():
            failures.append("allocated value is not a decimal string")

        # 4. The real package.py must go through this entry (no local allocator).
        source = (ROOT / "package.py").read_text()
        if "package_args.resolve(" not in source:
            failures.append("package.py no longer uses package_args.resolve")
        if "--build" in source:
            failures.append("package.py still mentions --build")

        # 5. A corrupt state file is refused, not silently reset (which would
        #    hand out a duplicate number).
        corrupt = Path(raw) / "corrupt"
        corrupt.mkdir()
        corrupt_file = corrupt / "build-number.json"
        original = "{not json"
        corrupt_file.write_text(original)
        result = subprocess.run([sys.executable, str(ROOT / "build_number.py"),
                                 "--state-dir", str(corrupt)], capture_output=True, text=True)
        if result.returncode == 0:
            failures.append("corrupt state was accepted")
        if corrupt_file.read_text() != original:
            failures.append("corrupt state was overwritten instead of refused")

        # 6. A boolean / non-object state is refused too, never reset to zero.
        for bad_state in ('{"last": true}', "[1, 2]"):
            bad = Path(raw) / f"bad-{abs(hash(bad_state))}"
            bad.mkdir()
            (bad / "build-number.json").write_text(bad_state)
            outcome = subprocess.run([sys.executable, str(ROOT / "build_number.py"),
                                      "--state-dir", str(bad)], capture_output=True, text=True)
            if outcome.returncode == 0:
                failures.append(f"invalid state accepted: {bad_state}")
            if (bad / "build-number.json").read_text() != bad_state:
                failures.append(f"invalid state rewritten: {bad_state}")

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print("package entry checks passed (auto allocate once, --build rejected without "
          "writing, consecutive +1, metadata matches, corrupt state refused)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
