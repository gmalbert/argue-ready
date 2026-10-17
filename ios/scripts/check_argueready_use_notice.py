"""Reject the removed ArgueReady use notice wherever it is placed in app UI."""

import pathlib
import re
import sys


FORBIDDEN = (
    r"use[\s_-]*notice",
    r"I will comply",
    r"applicable court rules",
    r"device[\s-]*use orders",
    r"Confirm that use of a phone",
    r"ArgueReady is a rehearsal and requirement-tracking aid, not legal advice",
    r"(?:acknowledge|agree|accept|confirm|comply|consent)[^\n\"]*(?:court rules|court orders|device[\s-]*use|legal advice)",
)


def violations(root):
    pattern = re.compile("|".join(FORBIDDEN), re.IGNORECASE)
    for directory in ("ArgueReady", "ArgueReadyWatch", "SharedCore", "WatchShared"):
        for source in sorted((root / directory).rglob("*.swift")):
            for number, line in enumerate(source.read_text().splitlines(), 1):
                if pattern.search(line):
                    yield f"{source}:{number}: error: Removed ArgueReady use notice or acknowledgment must not return."


def main():
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]
    failures = list(violations(root))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("ArgueReady use-notice regression check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
