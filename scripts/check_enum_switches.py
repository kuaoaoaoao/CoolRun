#!/usr/bin/env python3
"""Static check: find `switch` blocks that look non-exhaustive.

The project has no working `xcodebuild` on the dev machine, so this stands in
for one specific class of compile error: an enum gains a case and some
`switch` over it is not updated (or, worse, an `if case` chain silently
ignores it).

Heuristic, deliberately conservative:
  * collect every enum and its case names
  * collect every `switch` block (brace matched) that has no `default:`
  * if the block's `case .x` set is a strict subset of some enum's case set
    and covers at least half of it, report the missing cases

Limitations: enums that declare several cases on one line are only partially
parsed; switches over non-enum values are ignored.

Usage:
    python3 scripts/check_enum_switches.py [path ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ENUM_RE = re.compile(r"^\s*(?:public |internal |private |fileprivate )?enum (\w+)[^{]*\{")
CASE_LINE_RE = re.compile(r"^\s*case (\w+)\s*(?:=.*|\(.*)?$")
CASE_SHORT_RE = re.compile(r"^\s*case (\w+)\s*(?:=|,)")
SKIP_NAMES = {"let", "var", "is", "indirect"}


def collect_enums(paths: list[Path]) -> dict[str, list[set[str]]]:
    """Map enum name -> every declaration's case set (names are not unique)."""
    enums: dict[str, list[set[str]]] = {}
    for path in paths:
        lines = path.read_text(encoding="utf-8").splitlines()
        depth = 0
        cur: list | None = None  # [name, base_depth, cases]

        for line in lines:
            if cur is None:
                m = ENUM_RE.match(line)
                if m:
                    cur = [m.group(1), depth, set()]
            else:
                stripped = line.strip()
                if not stripped.startswith("case ."):
                    cm = CASE_LINE_RE.match(line) or CASE_SHORT_RE.match(line)
                    if cm and cm.group(1) not in SKIP_NAMES:
                        cur[2].add(cm.group(1))

            opens, closes = line.count("{"), line.count("}")
            depth += opens - closes

            if cur is not None and (opens or closes) and depth <= cur[1]:
                if cur[2]:
                    enums.setdefault(cur[0], []).append(cur[2])
                cur = None

    return enums


def find_switch_blocks(text: str):
    """Yield (start_line, body) for each `switch` block."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not re.search(r"\bswitch\b", line):
            continue
        depth = 0
        started = False
        body: list[str] = []
        for j in range(i, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            body.append(lines[j])
            if started and depth <= 0:
                yield i + 1, "\n".join(body)
                break


def case_names(line: str) -> set[str]:
    """All `.foo` names on the left of a `case` label.

    `case .a, .b: return .c` -> {a, b}; `.c` is a value, not a pattern.
    Colons inside parentheses (associated values) do not end the label.
    """
    stripped = line.strip()
    if not stripped.startswith("case "):
        return set()
    head = stripped[len("case "):]
    depth = 0
    cut = len(head)
    for idx, ch in enumerate(head):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif ch == ":" and depth == 0:
            cut = idx
            break
    return set(re.findall(r"\.(\w+)", head[:cut]))


def main() -> int:
    roots = [Path(p) for p in sys.argv[1:]] or [Path("CoolRun")]
    paths = sorted(p for root in roots for p in root.rglob("*.swift"))
    if not paths:
        print("no Swift files found")
        return 1

    enums = collect_enums(paths)
    all_decls = [cases for decls in enums.values() for cases in decls]
    findings = []

    for path in paths:
        text = path.read_text(encoding="utf-8")
        for line_no, body in find_switch_blocks(text):
            if re.search(r"^\s*(?:@unknown\s+)?default\s*:", body, re.MULTILINE):
                continue
            used: set[str] = set()
            for body_line in body.splitlines():
                used |= case_names(body_line)
            if len(used) < 2:
                continue
            # If the block is exhaustive for *some* enum declaration, the names
            # merely collide with another enum's cases (two different
            # healthy/warning/critical types, several nested `Status` enums…).
            if any(used == cases for cases in all_decls):
                continue
            for name, decls in enums.items():
                for cases in decls:
                    if used < cases and len(used & cases) >= max(2, len(cases) // 2):
                        findings.append((path, line_no, name, sorted(cases - used)))

    if not findings:
        print(f"OK: {len(all_decls)} enum declarations scanned, no obviously non-exhaustive switch")
        return 0

    for path, line_no, name, missing in findings:
        print(f"{path}:{line_no}  switch over {name} may be missing: {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
