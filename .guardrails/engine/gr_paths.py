"""Path globs with gitignore-flavoured semantics, shared by every path-based rule.

- A pattern without "/" matches the file's basename anywhere: "*.pem", ".env".
- A pattern containing "/" is anchored at the repo root: ".guardrails/**", "app/src/**/*.kt".
- A pattern starting with "~/" is anchored at the user's home directory and is
  matched against absolute paths, so rules can cover files outside the repo.
- "**" crosses directory boundaries; "*" and "?" don't.
- A leading "!" re-includes a path; the last matching pattern wins.
"""

from __future__ import annotations

import os
import re
from functools import cache

HOME = os.path.expanduser("~")


@cache
def _compile(glob: str) -> re.Pattern[str]:
    out: list[str] = []
    i, n = 0, len(glob)
    while i < n:
        c = glob[i]
        if glob.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif glob.startswith("**", i):
            out.append(".*")
            i += 2
        elif c == "*":
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "[" and "]" in glob[i + 1 :]:
            j = glob.index("]", i + 1)
            body = glob[i + 1 : j]
            if body.startswith("!"):
                body = "^" + body[1:]
            out.append("[" + body.replace("\\", "\\\\") + "]")
            i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    return re.compile("".join(out))


def matches(rel: str | None, abs_path: str | None, pattern: str) -> bool:
    """True if one path (given repo-relative and/or absolute) matches one glob."""
    if pattern.startswith("~/"):
        return abs_path is not None and bool(_compile(HOME + pattern[1:]).fullmatch(abs_path))
    if pattern.startswith("/"):
        return abs_path is not None and bool(_compile(pattern).fullmatch(abs_path))
    if rel is None:
        return False
    if "/" not in pattern:
        return bool(_compile(pattern).fullmatch(rel.rsplit("/", 1)[-1]))
    return bool(_compile(pattern).fullmatch(rel))


def match_any(rel: str | None, abs_path: str | None, patterns: list[str]) -> bool:
    """Gitignore semantics over a pattern list: last match wins, "!" negates."""
    hit = False
    for p in patterns:
        negate = p.startswith("!")
        if matches(rel, abs_path, p[1:] if negate else p):
            hit = not negate
    return hit


def resolve(root: str, path: str, cwd: str | None = None) -> tuple[str | None, str]:
    """Normalize a path as a tool or shell would see it.

    Returns (repo-relative POSIX path or None if outside the repo, absolute path).
    """
    p = path.replace("${HOME}", HOME).replace("$HOME", HOME)
    p = os.path.expanduser(p)
    if not os.path.isabs(p):
        p = os.path.join(cwd or root, p)
    abs_path = os.path.normpath(p)
    for base, candidate in ((root, abs_path), (os.path.realpath(root), os.path.realpath(abs_path))):
        try:
            if os.path.commonpath([base, candidate]) == base:
                rel = os.path.relpath(candidate, base).replace(os.sep, "/")
                return (None if rel == "." else rel), abs_path
        except ValueError:  # different drives on Windows
            continue
    return None, abs_path
