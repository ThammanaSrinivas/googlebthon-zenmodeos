"""Thin git wrappers: which files a check covers and where their bytes come from."""

from __future__ import annotations

import subprocess
from pathlib import Path


def _git(root: Path | str, *args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, check=False)


def _paths(out: bytes) -> list[str]:
    return [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]


def is_repo(root: Path) -> bool:
    return _git(root, "rev-parse", "--is-inside-work-tree").returncode == 0


def staged_files(root: Path) -> list[str]:
    return _paths(_git(root, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").stdout)


def tracked_files(root: Path) -> list[str]:
    return _paths(_git(root, "ls-files", "-z").stdout)


def changed_files(root: Path) -> list[str]:
    """Modified, added and untracked-but-not-ignored files in the working tree."""
    out = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all").stdout
    files: list[str] = []
    entries = out.split(b"\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2].decode(), entry[3:].decode("utf-8", "surrogateescape")
        if "R" in status or "C" in status:
            i += 1  # the next entry is the rename source
        if "D" not in status:
            files.append(path)
    return files


def read_staged(root: Path, rel: str) -> bytes | None:
    result = _git(root, "show", f":{rel}")
    return result.stdout if result.returncode == 0 else None


def staged_size(root: Path, rel: str) -> int:
    result = _git(root, "cat-file", "-s", f":{rel}")
    return int(result.stdout or 0) if result.returncode == 0 else 0


def is_ignored(root: Path, rel: str) -> bool:
    return _git(root, "check-ignore", "-q", "--no-index", rel).returncode == 0


def is_tracked(root: Path, rel: str) -> bool:
    return _git(root, "ls-files", "--error-unmatch", rel).returncode == 0


def current_branch(cwd: Path | str) -> str:
    return _git(cwd, "branch", "--show-current").stdout.decode().strip()


def config_get(root: Path, key: str) -> str:
    return _git(root, "config", "--get", key).stdout.decode().strip()


def config_set(root: Path, key: str, value: str) -> bool:
    return _git(root, "config", key, value).returncode == 0
