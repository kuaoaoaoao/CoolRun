#!/usr/bin/env python3
"""Static checks that catch the failure modes introduced by splitting files.

1. Two top-level types with the same name (a split gone wrong).
2. A `private` top-level type referenced from another file (invisible there).

Usage:
    python3 scripts/check_visibility.py [path ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TYPE_RE = re.compile(
    r"^(?:private |fileprivate |internal |public )?(?:final )?(?:struct|enum|class|actor) (\w+)"
)
GENERIC_NAMES = {
    "Array", "Optional", "Set", "Dictionary", "Result", "Data", "Date", "URL",
    "String", "Int", "Double", "Float", "Bool", "CGFloat", "Color", "View",
    "Binding", "UInt64", "Int64", "ByteCountFormatter",
}


def main() -> int:
    roots = [Path(p) for p in sys.argv[1:]] or [Path("CoolRun")]
    paths = sorted(p for root in roots for p in root.rglob("*.swift"))
    if not paths:
        print("no Swift files found")
        return 1

    sources = {p: p.read_text(encoding="utf-8") for p in paths}

    declarations: dict[str, list[tuple[Path, int, bool]]] = {}
    for path, text in sources.items():
        for line_no, line in enumerate(text.splitlines(), 1):
            m = TYPE_RE.match(line)
            if not m:
                continue
            name = m.group(1)
            is_private = line.startswith(("private ", "fileprivate "))
            declarations.setdefault(name, []).append((path, line_no, is_private))

    failures = 0

    for name, decls in sorted(declarations.items()):
        if name in GENERIC_NAMES or len(decls) < 2:
            continue
        # Same file: either `#if os(macOS) … #else …` branches or something the
        # compiler itself will reject — not a split artefact.
        if len({path for path, _, _ in decls}) == 1:
            continue
        # `private`/`fileprivate` declarations are file-scoped, so two of them in
        # different files do not clash. Only internal/public collisions are real.
        public_decls = [d for d in decls if not d[2]]
        if len(public_decls) > 1:
            print(f"DUPLICATE TYPE {name}:")
            for path, line_no, _ in public_decls:
                print(f"    {path}:{line_no}")
            failures += 1

    for name, decls in sorted(declarations.items()):
        if name in GENERIC_NAMES:
            continue
        if not all(is_private for _, _, is_private in decls):
            continue
        owners = {path for path, _, _ in decls}
        word = re.compile(rf"\b{re.escape(name)}\b")
        for path, text in sources.items():
            if path in owners:
                continue
            if word.search(text):
                print(f"PRIVATE LEAK {name} declared in {next(iter(owners))} but used in {path}")
                failures += 1

    if failures:
        print(f"\n{failures} problem(s) found")
        return 1

    print(f"OK: {len(declarations)} top-level types, no duplicates, no private leaks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
