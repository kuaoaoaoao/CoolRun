#!/usr/bin/env python3
"""扫描未本地化的用户可见中文字面量。

用法：
    python3 scripts/check_i18n.py            # 报告
    python3 scripts/check_i18n.py --strict   # 有未本地化文案时退出码 1

判定规则：
- 一个字符串字面量如果出现在同时带 `en:` 与 `zh:` 实参的调用里，视为已本地化
  （覆盖 LocalizedString.l、各文件内的 text(en:zh:ja:ko:) helper）。
- 注释里的中文不算。
- 白名单文件属于数据/模型提示词，不要求本地化。
- 枚举 rawValue 定义（`case foo = "中文"`）不参与检查：rawValue 是持久化/协议契约。
- 单行可用 `// i18n-allow: 原因` 标注为"故意保留"，注解独占一行时覆盖下一行。
  用它标注文化数据、给模型的提示词、日志等不该本地化的字面量，别用注解掩盖真文案。
- 另外检查 `LocalizedString.<分类>("key")` 的 key 是否真的存在于该分类字典里：
  不存在的 key 会原样显示成 `check_input` 这种英文标识符。

新增代码请遵守 docs/i18n-conventions.md。
"""

from __future__ import annotations

import os
import re
import sys

HAN = re.compile(r"[\u4e00-\u9fff]")

# 数据文件与模型提示词：内容本身不是界面文案，不参与检查。
WHITELIST = {
    "CoolRun/Core/LocalizedString.swift",            # 本地化字典本身
    "CoolRun/Modules/English/EnglishVocabulary.swift",      # 词库数据
    "CoolRun/Modules/English/EnglishContentRepository.swift",  # 例句/文章数据
    "CoolRun/Core/HolidayService.swift",             # 节假日数据表
    "CoolRun/Core/LunarCalendar.swift",              # 农历/节气名称表
    "CoolRun/Modules/Gold/GoldNewsClassifier.swift", # 新闻关键词表
    "CoolRun/Modules/Agent/AgentPrompts.swift",      # 给模型的提示词
    "CoolRun/Modules/Agent/AgentRecipe.swift",       # 配方（给模型看）
    "CoolRun/Modules/Agent/AgentTools.swift",        # 工具 schema（给模型看）
    "CoolRun/Modules/Agent/AgentGoldTools.swift",
    "CoolRun/Modules/Agent/AgentActionTools.swift",
    "CoolRun/Modules/Agent/ToolRegistry.swift",
}


# 行内豁免：`// i18n-allow: 原因`
ALLOW_MARK = re.compile(r"i18n-allow")
# 枚举 rawValue 定义：`case foo = "中文"`（`case .foo: return "中文"` 不算）
ENUM_RAW_VALUE = re.compile(r'^\s*case\s+[A-Za-z_]\w*\s*=\s*"')


def allowed_lines(raw: str) -> set:
    """带 i18n-allow 注解的行号；注解独占一行时同时豁免下一行。"""
    allow = set()
    for index, line in enumerate(raw.split("\n"), 1):
        if ALLOW_MARK.search(line):
            allow.add(index)
            if line.strip().startswith("//"):
                allow.add(index + 1)
    return allow


def strip_comments(src: str) -> str:
    """把 // 与 /* */ 注释抹成空格，保留字符串内容与行号。"""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            triple = src.startswith('"""', i)
            i += 3 if triple else 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if triple and src.startswith('"""', i):
                    i += 3
                    break
                if not triple and src[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def string_spans(src: str):
    """返回 (start, end, text) 的字符串字面量区间。"""
    spans = []
    i, n = 0, len(src)
    while i < n:
        if src[i] != '"':
            i += 1
            continue
        triple = src.startswith('"""', i)
        start = i
        i += 3 if triple else 1
        while i < n:
            if src[i] == "\\":
                i += 2
                continue
            if triple and src.startswith('"""', i):
                i += 3
                break
            if not triple and src[i] == '"':
                i += 1
                break
            i += 1
        spans.append((start, i, src[start:i]))
    return spans


def call_spans(src: str):
    """所有 `name(` 调用的括号区间。"""
    spans = []
    for m in re.finditer(r"[A-Za-z_][A-Za-z0-9_\.]*\s*\(", src):
        start = m.end() - 1
        depth = 0
        i, n = start, len(src)
        while i < n:
            c = src[i]
            if c == '"':
                triple = src.startswith('"""', i)
                i += 3 if triple else 1
                while i < n:
                    if src[i] == "\\":
                        i += 2
                        continue
                    if triple and src.startswith('"""', i):
                        i += 3
                        break
                    if not triple and src[i] == '"':
                        i += 1
                        break
                    i += 1
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        spans.append((start, i + 1))
    return spans


def scan(root: str):
    findings = {}
    allowed = set()
    enum_values = set()
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name).replace(os.sep, "/")
            if path in WHITELIST:
                continue
            raw = open(path, encoding="utf-8").read()
            allow = allowed_lines(raw)
            src = strip_comments(raw)
            localized = [
                (a, b)
                for (a, b) in call_spans(src)
                if re.search(r"\ben\s*:", src[a:b]) and re.search(r"\bzh\s*:", src[a:b])
            ]
            hits = []
            seen = set()
            for start, end, text in string_spans(src):
                if not HAN.search(text):
                    continue
                if any(a <= start < b for a, b in localized):
                    continue
                line = src.count("\n", 0, start) + 1
                line_start = src.rfind("\n", 0, start) + 1
                line_end = src.find("\n", start)
                snippet = src[line_start:line_end].strip()
                if line in allow:
                    allowed.add((path, line))
                    continue
                if ENUM_RAW_VALUE.match(snippet):
                    enum_values.add((path, line))
                    continue
                key = (line, snippet[:160])
                if key in seen:
                    continue
                seen.add(key)
                hits.append(key)
            if hits:
                findings[path] = hits
    return findings, len(allowed), len(enum_values)


DICT_PATH = "CoolRun/Core/LocalizedString.swift"
CATEGORY_FUNC = re.compile(r"static func (\w+)\(_ key: String[^)]*\)[^{]*\{")


def category_keys(src: str) -> dict:
    """从 LocalizedString 里提取每个分类函数认识的 key。"""
    keys = {}
    for m in CATEGORY_FUNC.finditer(src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
            i += 1
        keys[m.group(1)] = set(re.findall(r'case\s+"([^"]+)"', src[m.end():i]))
    return keys


def scan_category_keys(root: str):
    """找出调用了字典里不存在 key 的位置。"""
    keys = category_keys(strip_comments(open(DICT_PATH, encoding="utf-8").read()))
    missing = []
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name).replace(os.sep, "/")
            src = strip_comments(open(path, encoding="utf-8").read())
            for m in re.finditer(r'LocalizedString\.(\w+)\(\s*"([^"]+)"', src):
                category, key = m.group(1), m.group(2)
                if category in keys and key not in keys[category]:
                    line = src.count("\n", 0, m.start()) + 1
                    missing.append((path, line, f'{category}("{key}")'))
    return missing


def main() -> int:
    root = "CoolRun"
    findings, allowed, enum_values = scan(root)
    missing_keys = scan_category_keys(root)
    total = sum(len(v) for v in findings.values())
    skipped = f"（另有 {allowed} 行 i18n-allow 标注、{enum_values} 行枚举 rawValue 定义属故意保留）"
    if not findings and not missing_keys:
        print(f"OK: 没有发现未本地化的中文字面量 {skipped}")
        print("OK: 分类 key 调用全部命中字典")
        return 0
    for path, hits in sorted(findings.items(), key=lambda kv: -len(kv[1])):
        print(f"\n{path}  ({len(hits)})")
        for line, snippet in hits:
            print(f"  {line}: {snippet}")
    if missing_keys:
        print("\n调用了字典里不存在的 key（会原样显示成英文标识符）：")
        for path, line, label in missing_keys:
            print(f"  {path}:{line}  {label}")
    print(f"\n合计 {total} 处待处理，分布在 {len(findings)} 个文件 {skipped}")
    return 1 if "--strict" in sys.argv else 0


if __name__ == "__main__":
    sys.exit(main())
