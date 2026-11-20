"""Rule evaluation. Every entry point returns Violations; nothing here prints or exits.

Entry points by where they run:
  check_command  PreToolUse(Bash)            command / git_push_branch / secret /
                                             protect_path / read_protect
  check_write    PreToolUse(Edit|Write|...)  protect_path / secret / content(stage=pre)
  check_read     PreToolUse(Read|Grep)       read_protect
  check_text     PostToolUse, commit, CI     content / secret / source_of_truth /
                                             max_lines / required_tags / duplicate_literal
  collect        pre-commit, CI, Stop hook   check_text over a file set + forbidden_file
                                             / max_file_size, with the baseline applied
"""

from __future__ import annotations

import os
import re
from collections import Counter, defaultdict
from dataclasses import dataclass

import gr_git
from gr_config import Config, Rule
from gr_literals import Literal, counted, literals
from gr_paths import match_any, resolve
from gr_shell import Command, parse

MAX_SCANNED_LINE = 20_000  # skip minified blobs; nothing human-written is this long

# Programs that may name a protected path without modifying it.
READ_ONLY_PROGRAMS = {
    "cat", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag", "ack", "ls", "tree",
    "find", "fd", "diff", "cmp", "wc", "file", "stat", "du", "jq", "yq", "bat", "sha1sum", "sha256sum",
    "md5sum", "shasum", "test", "[", "realpath", "readlink", "dirname", "basename", "echo", "printf",
    "cd", "pushd", "sed", "awk", "gawk", "sort", "uniq", "cut", "nl", "od", "xxd", "hexdump", "strings",
}
GIT_READ_ONLY = {"status", "diff", "log", "show", "blame", "ls-files", "check-ignore", "grep", "rev-parse",
                 "cat-file", "ls-tree", "add", "commit", "shortlog"}
GR_SAFE_SUBCOMMANDS = {"", "check", "test", "list", "explain", "doctor", "hook", "setup", "version",
                       "help", "-h", "--help"}
# Programs that may name a secret file without putting its contents on screen.
SECRET_SAFE_PROGRAMS = {"ls", "stat", "test", "[", "file", "touch", "chmod", "mkdir", "cd", "pushd",
                        "source", ".", "docker", "docker-compose", "podman", "podman-compose", "env-cmd",
                        "dotenv", "echo", "printf", "realpath", "dirname", "basename"}
GIT_SECRET_SAFE = {"rm", "check-ignore", "ls-files", "status", "mv"}


@dataclass
class Violation:
    rule: Rule
    path: str = ""
    line: int | None = None
    found: str = ""
    note: str = ""
    count: int = 0  # measured value for size-style rules (lines, KB)


# ── commands ──────────────────────────────────────────────────────────────────

def check_command(cfg: Config, command: str, cwd: str) -> list[Violation]:
    parsed = parse(command)
    out: list[Violation] = []
    for rule in cfg.of("command"):
        found = _search(rule.regex, [command] if rule.scope == "raw" else parsed.views)
        if found is not None:
            out.append(Violation(rule, found=_snip(found)))
    for rule in cfg.of("git_push_branch"):
        branch = _protected_push(cfg, rule, parsed.commands, cwd)
        if branch:
            out.append(Violation(rule, found=f"push to '{branch}'"))
    if not _writes_secret_file(cfg, parsed.commands, cwd):
        for rule in cfg.of("secret"):
            found = _search(rule.regex, [command])
            if found is not None:
                out.append(Violation(rule, found=_redact(found), note="in a shell command"))
    for rule in cfg.of("protect_path"):
        target = _modifies_protected(cfg, rule, parsed.commands, cwd)
        if target:
            out.append(Violation(rule, path=target, found="shell command modifies a protected path"))
    for rule in cfg.of("read_protect"):
        target = _reads_secret(cfg, rule, parsed.commands, cwd)
        if target:
            out.append(Violation(rule, path=target, found="shell command reads a secret file"))
    return out


def _search(regex: re.Pattern[str] | None, texts: list[str]) -> str | None:
    for text in texts:
        m = regex.search(text) if regex else None
        if m:
            return m.group(0)
    return None


def _path_candidates(word: str) -> list[str]:
    if not word or (word.startswith("-") and "=" not in word):
        return []
    out = [word]
    if "=" in word:
        out.append(word.split("=", 1)[1])
    if word.startswith("@"):
        out.append(word[1:])
    return [w for w in out if w]


def _hits(cfg: Config, patterns: list[str], word: str, cwd: str) -> bool:
    for candidate in _path_candidates(word):
        rel, ab = resolve(str(cfg.root), candidate, cwd)
        if match_any(rel, ab, patterns):
            return True
    return False


def _guardrails_cli_subcommand(c: Command) -> str | None:
    """If c runs the guardrails CLI, its subcommand ("" for none); else None."""
    def is_cli(word: str) -> bool:
        return word.endswith(".guardrails/gr") or word.endswith("gr.py") or word == "gr"
    if is_cli(c.program):
        return c.args[0] if c.args else ""
    if c.name.startswith(("python", "py", "sh", "bash")) and c.args and is_cli(c.args[0]):
        return c.args[1] if len(c.args) > 1 else ""
    return None


def _read_only(c: Command) -> bool:
    gr_sub = _guardrails_cli_subcommand(c)
    if gr_sub is not None:
        return gr_sub in GR_SAFE_SUBCOMMANDS
    name, args = c.name, c.args
    if name == "git":
        return c.subcommand() in GIT_READ_ONLY
    if name not in READ_ONLY_PROGRAMS:
        return False
    if name == "sed" and any(re.fullmatch(r"-[a-zA-Z]*i.*|--in-place.*", a) for a in args):
        return False
    if name == "find" and any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint") for a in args):
        return False
    if name in ("awk", "gawk") and any("inplace" in a for a in args):
        return False
    return True


def _modifies_protected(cfg: Config, rule: Rule, commands: list[Command], cwd: str) -> str | None:
    for c in commands:
        for target in c.out_targets:
            if _hits(cfg, rule.paths, target, cwd):
                return target
        named = [w for w in c.words if _hits(cfg, rule.paths, w, cwd)]
        if named and not _read_only(c):
            return named[0]
    return None


def _reads_secret(cfg: Config, rule: Rule, commands: list[Command], cwd: str) -> str | None:
    for c in commands:
        for target in c.in_targets:
            if _hits(cfg, rule.paths, target, cwd):
                return target
        named = [w for w in c.words if _hits(cfg, rule.paths, w, cwd)]
        if not named or c.name in SECRET_SAFE_PROGRAMS:
            continue
        if c.name == "git" and c.subcommand() in GIT_SECRET_SAFE:
            continue
        return named[0]
    return None


def _writes_secret_file(cfg: Config, commands: list[Command], cwd: str) -> bool:
    """`cat > .env <<EOF` is how a secret is *supposed* to be stored - don't flag it."""
    secret_files = cfg.settings["secret_files"]
    for c in commands:
        targets = c.out_targets + (c.args if c.name == "tee" else [])
        if any(_hits(cfg, secret_files, t, cwd) for t in targets):
            return True
    return False


def _protected_push(cfg: Config, rule: Rule, commands: list[Command], cwd: str) -> str | None:
    branches = rule.branches or cfg.protected_branches()
    for c in commands:
        if c.name != "git" or c.subcommand() != "push":
            continue
        args, git_cwd = c.args, cwd
        if "-C" in args[:args.index("push")]:
            git_cwd = os.path.join(cwd, args[args.index("-C") + 1])
        rest = args[args.index("push") + 1:]
        if "--all" in rest or "--mirror" in rest:
            return "--all/--mirror"
        positional, skip = [], False
        for a in rest:
            if skip:
                skip = False
            elif a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
                skip = True
            elif not a.startswith("-"):
                positional.append(a)
        if len(positional) <= 1:
            if "--tags" in rest:
                continue
            dests = [gr_git.current_branch(git_cwd)]
        else:
            dests = []
            for spec in positional[1:]:
                dest = spec.lstrip("+").split(":", 1)[-1]
                if dest in ("HEAD", "@"):
                    dest = gr_git.current_branch(git_cwd)
                dests.append(dest.removeprefix("refs/heads/"))
        for d in dests:
            if d in branches:
                return d
    return None


# ── tool writes and reads ─────────────────────────────────────────────────────

def _applies(cfg: Config, rule: Rule, rel: str | None, ab: str | None) -> bool:
    if rel is None or match_any(rel, ab, cfg.settings["exclude"]):
        return False
    if rule.kind == "source_of_truth" and rel == rule.source:
        return False
    return match_any(rel, ab, rule.paths) and not match_any(rel, ab, rule.exclude)


def check_write(cfg: Config, path: str, texts: list[str], cwd: str) -> list[Violation]:
    rel, ab = resolve(str(cfg.root), path, cwd)
    shown = rel or ab
    out: list[Violation] = []
    for rule in cfg.of("protect_path"):
        if match_any(rel, ab, rule.paths):
            out.append(Violation(rule, path=shown, found="edit to a protected file"))
    secret_file = match_any(rel, ab, cfg.settings["secret_files"])
    for rule in cfg.of("secret", "content"):
        if rule.stage != "pre" or (rule.kind == "secret" and secret_file) or not _applies(cfg, rule, rel, ab):
            continue
        for text in texts:
            for i, line in enumerate(text.splitlines(), 1):
                m = rule.regex.search(line) if len(line) <= MAX_SCANNED_LINE else None
                if m:
                    found = _redact(m.group(0)) if rule.kind == "secret" else _snip(m.group(0))
                    out.append(Violation(rule, path=shown, found=found, note=f"line {i} of the new text"))
    return out


def check_read(cfg: Config, path: str, cwd: str) -> list[Violation]:
    rel, ab = resolve(str(cfg.root), path, cwd)
    return [Violation(rule, path=rel or ab, found="read of a secret file")
            for rule in cfg.of("read_protect") if match_any(rel, ab, rule.paths)]


# ── file contents ─────────────────────────────────────────────────────────────

_sot_cache: dict[str, re.Pattern[str] | None] = {}


def _source_of_truth_regex(cfg: Config, rule: Rule) -> re.Pattern[str] | None:
    if rule.id not in _sot_cache:
        try:
            text = (cfg.root / rule.source).read_text(errors="replace")
        except OSError:
            text = ""
        found = [m if isinstance(m, str) else m[0] for m in rule.extract.findall(text)] if rule.extract else []
        literals = sorted(set(filter(None, found)), key=len, reverse=True)
        _sot_cache[rule.id] = (re.compile(r"([\"'`])(" + "|".join(map(re.escape, literals)) + r")\1")
                               if literals else None)
    return _sot_cache[rule.id]


def check_text(cfg: Config, rel: str, text: str) -> list[Violation]:
    out: list[Violation] = []
    lines = text.splitlines()
    secret_file = match_any(rel, None, cfg.settings["secret_files"])
    for rule in cfg.of("content", "secret", "source_of_truth"):
        if (rule.kind == "secret" and secret_file) or not _applies(cfg, rule, rel, None):
            continue
        regex = _source_of_truth_regex(cfg, rule) if rule.kind == "source_of_truth" else rule.regex
        if regex is None:
            continue
        for i, line in enumerate(lines, 1):
            m = regex.search(line) if len(line) <= MAX_SCANNED_LINE else None
            if m:
                found = _redact(m.group(0)) if rule.kind == "secret" else _snip(line.strip())
                out.append(Violation(rule, path=rel, line=i, found=found))
    for rule in cfg.of("max_lines"):
        if _applies(cfg, rule, rel, None) and len(lines) > rule.max:
            out.append(Violation(rule, path=rel, found=f"{len(lines)} lines (limit {rule.max})", count=len(lines)))
    for rule in cfg.of("required_tags"):
        if _applies(cfg, rule, rel, None):
            for tag in rule.tags:
                if tag not in text:
                    out.append(Violation(rule, path=rel, found=f"missing {tag}"))
    for rule in cfg.of("duplicate_literal"):
        if _applies(cfg, rule, rel, None):
            out += _duplicate_literals(cfg, rule, rel, text)
    return out


# Per (root, rule): literal text -> every (file, line) holding it, across the rule's paths on
# disk. Built once per process: one hook call, or one `gr check` over the whole tree.
_literal_index: dict[tuple[str, str], dict[str, list[tuple[str, int]]]] = {}


def _counted_literals(rule: Rule, rel: str, text: str) -> list[Literal]:
    return [lit for lit in literals(text, os.path.splitext(rel)[1]) if counted(lit, rule.min_length)]


def _index(cfg: Config, rule: Rule) -> dict[str, list[tuple[str, int]]]:
    key = (str(cfg.root), rule.id)
    if key not in _literal_index:
        root = cfg.root
        files = (sorted(set(gr_git.tracked_files(root)) | set(gr_git.changed_files(root)))
                 if gr_git.is_repo(root) else _walk(cfg))
        index: dict[str, list[tuple[str, int]]] = defaultdict(list)
        for rel in files:
            if not _applies(cfg, rule, rel, None):
                continue
            try:
                data = (root / rel).read_bytes()
            except OSError:
                continue
            if b"\0" in data[:8192]:
                continue
            for lit in _counted_literals(rule, rel, data.decode("utf-8", "replace")):
                index[lit.text].append((rel, lit.line))
        _literal_index[key] = index
    return _literal_index[key]


def _duplicate_literals(cfg: Config, rule: Rule, rel: str, text: str) -> list[Violation]:
    """Copies of one text across the rule's files; `text` stands in for rel's copy on disk."""
    own = _counted_literals(rule, rel, text)
    if not own:
        return []
    index = _index(cfg, rule)
    mine = Counter(lit.text for lit in own)
    out: list[Violation] = []
    for lit in own:
        elsewhere = [(p, n) for p, n in index.get(lit.text, []) if p != rel]
        total = mine[lit.text] + len(elsewhere)
        if total > rule.max:
            others = ", ".join(f"{p}:{n}" for p, n in elsewhere[:3]) + (", …" if len(elsewhere) > 3 else "")
            out.append(Violation(rule, path=rel, line=lit.line, found=_snip(f'"{lit.text}"'),
                                 note=f"{total} copies, at most {rule.max}" + (f"; also {others}" if others else "")))
    return out


def check_meta(cfg: Config, files: list[str], mode: str) -> list[Violation]:
    """forbidden_file / max_file_size: properties of the file, not its text."""
    out: list[Violation] = []
    state = {"staged": "staged for commit", "all": "tracked by git",
             "changed": "untracked and not gitignored - one `git add .` from being committed"}
    for rel in files:
        ab = str(cfg.root / rel)
        for rule in cfg.of("forbidden_file"):
            if match_any(rel, ab, rule.paths) and not match_any(rel, ab, rule.exclude):
                if mode == "changed" and gr_git.is_tracked(cfg.root, rel):
                    found = "tracked by git"
                elif mode == "paths" and gr_git.is_ignored(cfg.root, rel):
                    continue
                else:
                    found = state.get(mode, "not gitignored")
                out.append(Violation(rule, path=rel, found=found))
        for rule in cfg.of("max_file_size"):
            if match_any(rel, ab, cfg.settings["exclude"]) or (rule.paths and not _applies(cfg, rule, rel, ab)):
                continue
            size = gr_git.staged_size(cfg.root, rel) if mode == "staged" else _size(ab)
            kb = (size + 1023) // 1024
            if kb > rule.max_kb:
                out.append(Violation(rule, path=rel, found=f"{kb} KB (limit {rule.max_kb} KB)", count=kb))
    return out


def _size(path: str) -> int:
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


# ── file sets and the baseline ────────────────────────────────────────────────

def collect(cfg: Config, mode: str, paths: list[str] | None = None) -> list[Violation]:
    """mode: "staged" (pre-commit), "changed" (Stop hook), "all" (CI) or "paths"."""
    root = cfg.root
    if paths:
        mode = "paths"
        files = [rel for rel, _ in (resolve(str(root), p) for p in paths) if rel]
    elif mode == "staged":
        files = gr_git.staged_files(root)
    elif mode == "changed":
        files = gr_git.changed_files(root)
    else:
        files = gr_git.tracked_files(root) if gr_git.is_repo(root) else _walk(cfg)
    out: list[Violation] = []
    for rel in files:
        if mode == "staged":
            data = gr_git.read_staged(root, rel)
        else:
            try:
                data = (root / rel).read_bytes() if (root / rel).is_file() else None
            except OSError:
                data = None
        if data is not None and b"\0" not in data[:8192]:
            out += check_text(cfg, rel, data.decode("utf-8", "replace"))
    out += check_meta(cfg, [f for f in files if (root / f).exists() or mode == "staged"], mode)
    return apply_baseline(cfg, out)


def _walk(cfg: Config) -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(cfg.root):
        rel_dir = os.path.relpath(dirpath, cfg.root).replace(os.sep, "/")
        rel_dir = "" if rel_dir == "." else rel_dir + "/"
        dirnames[:] = [d for d in dirnames if not match_any(rel_dir + d + "/x", None, cfg.settings["exclude"])]
        files += [rel_dir + f for f in filenames]
    return files


def apply_baseline(cfg: Config, violations: list[Violation]) -> list[Violation]:
    groups: dict[tuple[str, str], list[Violation]] = defaultdict(list)
    for v in violations:
        groups[(v.rule.id, v.path)].append(v)
    dropped: set[int] = set()
    for (rule_id, path), group in groups.items():
        allowed = cfg.baseline.get(rule_id, {}).get(path)
        kind = group[0].rule.kind
        if allowed is None or kind == "required_tags":
            continue
        if kind in ("max_lines", "max_file_size"):
            if group[0].count <= allowed:
                dropped.update(map(id, group))
            else:
                group[0].note = f"grandfathered at {allowed}; it may not grow past that"
        elif len(group) <= allowed:
            dropped.update(map(id, group))
        else:
            for v in group:
                v.note = f"{len(group)} in this file; the baseline allows {allowed} (pre-existing debt), not more"
    return [v for v in violations if id(v) not in dropped]


def baseline_from(violations: list[Violation]) -> dict[str, dict[str, int]]:
    data: dict[str, dict[str, int]] = defaultdict(dict)
    for v in violations:
        if v.rule.kind == "required_tags":
            continue
        if v.rule.kind in ("max_lines", "max_file_size"):
            data[v.rule.id][v.path] = v.count
        else:
            data[v.rule.id][v.path] = data[v.rule.id].get(v.path, 0) + 1
    return {k: dict(sorted(v.items())) for k, v in sorted(data.items())}


# ── self-test support ─────────────────────────────────────────────────────────

def example_hits(cfg: Config, rule: Rule, example: str) -> bool:
    """Does `rule` fire on one of its own bad/good examples?"""
    if rule.kind == "command":
        return _search(rule.regex, [example] if rule.scope == "raw" else parse(example).views) is not None
    if rule.kind == "git_push_branch":
        # Examples exercise the refspec parsing, so they run against the default branch set:
        # a project dropping "master" from protected_branches doesn't make the parser wrong.
        probe = Rule(**{**rule.__dict__, "branches": rule.branches or ["main", "master"]})
        return _protected_push(cfg, probe, parse(example).commands, str(cfg.root)) is not None
    if rule.kind in ("secret", "content"):
        return _search(rule.regex, [example]) is not None
    if rule.kind == "source_of_truth":
        return _search(_source_of_truth_regex(cfg, rule), [example]) is not None
    if rule.kind == "duplicate_literal":
        # An example is read as the language the rule's paths name, so "#" means what it would there.
        ext = next((e for e in (os.path.splitext(p)[1] for p in rule.paths) if e), "")
        copies = Counter(lit.text for lit in literals(example, ext) if counted(lit, rule.min_length))
        return any(n > rule.max for n in copies.values())
    if rule.kind in ("protect_path", "read_protect", "forbidden_file"):
        rel, ab = resolve(str(cfg.root), example)
        if example.startswith("~/"):
            rel = None
        return match_any(rel, ab, rule.paths) and not match_any(rel, ab, rule.exclude)
    return False


def _snip(text: str, limit: int = 100) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit - 1] + "…"


def _redact(secret: str) -> str:
    return f"{secret[:4]}… ({len(secret)} chars, redacted)"

