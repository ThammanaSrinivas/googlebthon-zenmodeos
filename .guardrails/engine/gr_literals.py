"""String literals in source text, for `duplicate_literal` rules.

A small lexer, not a parser: it knows where strings and comments begin and end, so text in
comments and code is never mistaken for a literal. Two comment families:
  C-family (default)  // line, /* block */  - Kotlin, Java, JS/TS, Swift, Go, C#, Dart, Rust…
  hash                # line                - Python, Ruby, shell, YAML, TOML
Strings: "…", '…', `…`, and triple-quoted \"\"\"…\"\"\" / '''…''' (raw: no escapes). A ${…}
template inside a string is scanned as code, so a literal nested in it is found too.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

HASH_COMMENT_EXTS = {".py", ".pyi", ".rb", ".sh", ".bash", ".zsh", ".pl", ".r", ".toml", ".yml", ".yaml",
                     ".ex", ".exs", ".cr", ".nim", ".jl", ".tf"}
NESTING_BLOCK_COMMENT_EXTS = {".kt", ".kts", ".swift", ".rs", ".scala", ".dart"}
MIN_LETTERS = 6  # once placeholders are stripped: "%s: %d" and "${a}/${b}" are formats, not text

_PLACEHOLDER = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_]\w*|\{[^{}]*\}|%[-+ #0-9.]*[a-zA-Z]")
# A literal right after these is an argument to an annotation/decorator, or a module path.
_EXEMPT_PREFIX = re.compile(
    r"@[\w.]+\s*\([^()]*$"                       # @Suppress("…"), @app.route("…")
    r"|^\s*(import|export|package|using)\b"      # import x from "…", package "…"
    r"|\bfrom\s*$|\b(require|import)\s*\(\s*$"   # } from "…", require("…"), import("…")
    r"|^\s*#\s*(include|import)\b"               # #include "…"
)


@dataclass(frozen=True)
class Literal:
    text: str    # the literal's source between its quotes, escapes and ${templates} verbatim
    line: int    # 1-based line it opens on
    prefix: str  # code on that line before the opening quote


def literals(src: str, ext: str = "") -> list[Literal]:
    """Every string literal in `src`; `ext` (".kt", ".py", …) picks the comment syntax."""
    hash_comments = ext.lower() in HASH_COMMENT_EXTS
    nesting = ext.lower() in NESTING_BLOCK_COMMENT_EXTS
    n = len(src)
    found: list[Literal] = []

    def make(start: int, body_start: int, end: int) -> None:
        line_start = src.rfind("\n", 0, start) + 1
        found.append(Literal(src[body_start:end], src.count("\n", 0, start) + 1, src[line_start:start]))

    def code(i: int, in_template: bool) -> int:
        depth = 0
        while i < n:
            c = src[i]
            if (c == "#" and hash_comments) or (c == "/" and src.startswith("//", i) and not hash_comments):
                i = src.find("\n", i)
                if i < 0:
                    return n
                continue
            if c == "/" and src.startswith("/*", i) and not hash_comments:
                i = _block_comment(src, i, nesting)
                continue
            if c in "\"'`":
                i = string(i)
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                if depth == 0 and in_template:
                    return i + 1
                depth -= 1
            i += 1
        return n

    def string(start: int) -> int:
        quote = src[start]
        triple = quote != "`" and src.startswith(quote * 3, start)
        close = quote * 3 if triple else quote
        i = body = start + len(close)
        while i < n:
            if src.startswith(close, i):
                if triple:
                    while src.startswith(close + quote, i):  # \"\"\"…\"\"\"\" ends on the last three
                        i += 1
                make(start, body, i)
                return i + len(close)
            c = src[i]
            if c == "\\" and not triple:
                i += 2
            elif c == "\n" and quote != "`" and not triple:
                make(start, body, i)  # unterminated on its line: stop, don't swallow the file
                return i + 1
            elif c == "$" and src.startswith("${", i) and quote != "'":
                i = code(i + 2, True)
            else:
                i += 1
        return n

    code(0, False)
    return found


def _block_comment(src: str, i: int, nesting: bool) -> int:
    depth, i = 1, i + 2
    while i < len(src) and depth:
        if nesting and src.startswith("/*", i):
            depth, i = depth + 1, i + 2
        elif src.startswith("*/", i):
            depth, i = depth - 1, i + 2
        else:
            i += 1
    return i


def counted(lit: Literal, min_length: int) -> bool:
    """Is `lit` text worth one spelling: long enough, wordy enough, and not an exempt position?"""
    if len(lit.text) < min_length:
        return False
    if sum(ch.isalpha() for ch in _PLACEHOLDER.sub("", lit.text)) < MIN_LETTERS:
        return False
    return not _EXEMPT_PREFIX.search(lit.prefix)
