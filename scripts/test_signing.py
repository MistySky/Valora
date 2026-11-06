#!/usr/bin/env python3
"""Verify the fixed Valora self-signed identity yields a certificate DR.

Two tiny probes with different code (different cdhash) are signed with the same
identity and identifier. Each must satisfy the other's designated requirement,
which is the property that lets TCC survive an app upgrade.

No media, calendar, Bluetooth, permission or user data is touched.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

IDENTITY = "Valora Self-Signed"
IDENTIFIER = "com.wangqing.valora.signing-probe"


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def fail(message: str) -> None:
    print("SIGNING CHECK FAILED:", message)
    raise SystemExit(1)


def main() -> int:
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
    text = (identities.stdout or "") + (identities.stderr or "")
    match = re.search(r'\b([0-9A-F]{40})\b\s+"' + re.escape(IDENTITY) + r'"', text)
    if not match:
        fail(f"missing valid identity {IDENTITY!r}")
    sha1 = match.group(1).upper()

    with tempfile.TemporaryDirectory(prefix="valora-signing-probe-") as folder:
        root = Path(folder)
        probes: list[Path] = []
        for index, value in enumerate((1, 2), start=1):
            source = root / f"probe{index}.c"
            binary = root / f"probe{index}"
            source.write_text(f"volatile int marker{index} = {value};\nint main(void){{return marker{index};}}\n")
            compile_result = run(["xcrun", "clang", "-arch", "arm64",
                                  "-mmacosx-version-min=27.0",
                                  "-o", str(binary), str(source)])
            if compile_result.returncode != 0:
                fail("probe compile failed: " + compile_result.stderr)
            signed = run(["codesign", "--force", "--sign", IDENTITY,
                          "--identifier", IDENTIFIER, "--options", "runtime",
                          "--timestamp=none", str(binary)])
            if signed.returncode != 0:
                fail("probe signing failed: " + signed.stderr)
            probes.append(binary)

        requirements: list[str] = []
        cdhashes: list[str] = []
        for binary in probes:
            detail = run(["codesign", "-d", "-r-", str(binary)])
            output = (detail.stdout or "") + (detail.stderr or "")
            marker = "designated =>"
            index = output.find(marker)
            if index < 0:
                fail("probe has no designated requirement")
            requirement = output[index + len(marker):].strip().splitlines()[0].strip()
            requirements.append(requirement)
            verbose = run(["codesign", "-d", "--verbose=4", str(binary)])
            verbose_text = (verbose.stdout or "") + (verbose.stderr or "")
            cdhash = re.search(r"CDHash=([0-9a-f]+)", verbose_text)
            if not cdhash:
                fail("probe has no cdhash")
            cdhashes.append(cdhash.group(1))

        if cdhashes[0] == cdhashes[1]:
            fail("probes unexpectedly share a cdhash")
        if requirements[0] != requirements[1]:
            fail("same identity/identifier produced different requirements")
        if 'certificate leaf = H"' not in requirements[0]:
            fail("requirement is not certificate-based: " + requirements[0])
        if 'cdhash' in requirements[0].lower():
            fail("requirement still contains a cdhash")
        if sha1.lower() not in requirements[0].lower():
            fail("requirement leaf does not match the selected identity")

        # Cross-verify: each probe satisfies the other's stable requirement.
        for binary, requirement in ((probes[1], requirements[0]), (probes[0], requirements[1])):
            verified = run(["codesign", "--verify", "--strict", "--verbose=2",
                            "-R", "=" + requirement, str(binary)])
            if verified.returncode != 0:
                fail("cross-version requirement failed: " +
                     ((verified.stdout or "") + (verified.stderr or "")))

    print("signing checks passed: certificate DR, different cdhash, cross-version match")
    print("certificate leaf sha1:", sha1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
