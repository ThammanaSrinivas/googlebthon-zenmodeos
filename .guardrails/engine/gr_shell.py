"""Just enough shell parsing for guardrails: what would run, never evaluated.

parse(cmd) returns two things:

views     The strings `command` rules match against: the command with quoted text
          and data heredocs blanked, so a commit message that merely *mentions*
          `git push --force` doesn't trip the force-push rule. Code a shell would
          execute is pulled back out and parsed recursively: `bash -c '...'`,
          `eval "..."`, `ssh host '...'`, `$(...)` inside double quotes, and
          heredocs fed to a shell.

commands  One Command per simple command (quotes removed, redirects split out), so
          path rules can ask "which program touches which file, and how".

It is a heuristic, not a shell: it exists to catch accidents and make the rule
that fired explain itself, not to contain a hostile process.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field

SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish", "su"}
# Words that run the *next* word as the program.
WRAPPERS = {"sudo", "doas", "env", "command", "builtin", "exec", "time", "nohup", "nice",
            "ionice", "timeout", "stdbuf", "xargs", "watch"}
KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while",
            "until", "for", "in", "case", "esac", "select", "function"}

_HEREDOC = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_REDIRECT = re.compile(r"(?:\d+|&)?(>>|>\||>|<)(.*)", re.S)
_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.S)
_SEPARATORS = set(";&|()`\n")
MAX_DEPTH = 4


@dataclass
class Command:
    words: list[str]
    out_targets: list[str] = field(default_factory=list)
    in_targets: list[str] = field(default_factory=list)

    @property
    def program_index(self) -> int:
        i, words = 0, self.words
        while i < len(words):
            w = words[i]
            if w in KEYWORDS or _ASSIGNMENT.fullmatch(w):
                i += 1
                continue
            if os.path.basename(w) in WRAPPERS:
                i += 1
                while i < len(words) and (words[i].startswith("-") or _ASSIGNMENT.fullmatch(words[i])
                                          or re.fullmatch(r"\d+[smhd]?", words[i])):
                    i += 1
                continue
            return i
        return len(words)

    @property
    def program(self) -> str:
        i = self.program_index
        return self.words[i] if i < len(self.words) else ""

    @property
    def name(self) -> str:
        return os.path.basename(self.program)

    @property
    def args(self) -> list[str]:
        return self.words[self.program_index + 1:]

    def subcommand(self) -> str:
        """First non-option argument, skipping git-style `-C dir` / `-c k=v` pairs."""
        args, i = self.args, 0
        while i < len(args):
            a = args[i]
            if a in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
                i += 2
                continue
            if a.startswith("-"):
                i += 1
                continue
            return a
        return ""


@dataclass
class Parsed:
    views: list[str]
    commands: list[Command]


def parse(cmd: str, _depth: int = 0) -> Parsed:
    view: list[str] = []
    nested: list[str] = []
    commands: list[Command] = []
    words: list[str] = []
    cur: list[str] = []
    in_word = False
    heredocs: list[tuple[str, bool, bool]] = []
    i, n = 0, len(cmd)

    def flush_word() -> None:
        nonlocal in_word
        if in_word:
            words.append("".join(cur))
            cur.clear()
            in_word = False

    def flush_command() -> None:
        flush_word()
        if words:
            commands.append(_to_command(words))
        words.clear()

    def pending_words() -> list[str]:
        return words + (["".join(cur)] if in_word else [])

    while i < n:
        c = cmd[i]
        if c == "\\":
            view.append(cmd[i:i + 2])
            cur.append(cmd[i + 1:i + 2])
            in_word = True
            i += 2
            continue
        if c in "'\"" or cmd.startswith("$'", i):
            ansi = c == "$"
            quote = "'" if ansi else c
            start = i + (2 if ansi else 1)
            end, substitutions = _scan_quoted(cmd, start, quote, escapes=ansi or quote == '"')
            content = cmd[start:end]
            if _is_code_argument(pending_words()):
                nested.append(content)
            else:
                nested.extend(substitutions)
            view.append(cmd[i:start] + " " * len(content) + quote)
            cur.append(content)
            in_word = True
            i = end + 1
            continue
        if cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            m = _HEREDOC.match(cmd, i)
            if m:
                flush_word()
                heredocs.append((m.group(3), m.group(1) == "-", _feeds_a_shell(words)))
                view.append(m.group(0))
                i = m.end()
                continue
        if c == "&" and (cmd[i - 1:i] == ">" or cmd[i + 1:i + 2] == ">"):
            view.append(c)  # 2>&1, &>file: part of a redirect, not a separator
            cur.append(c)
            in_word = True
            i += 1
            continue
        if c in _SEPARATORS:
            flush_command()
            view.append(c)
            i += 1
            if c == "\n" and heredocs:
                i = _consume_heredocs(cmd, i, heredocs, nested)
                heredocs.clear()
            continue
        if c.isspace():
            flush_word()
            view.append(c)
            i += 1
            continue
        view.append(c)
        cur.append(c)
        in_word = True
        i += 1
    flush_command()

    views = ["".join(view)]
    if _depth < MAX_DEPTH:
        for code in nested:
            sub = parse(code, _depth + 1)
            views += sub.views
            commands += sub.commands
    return Parsed(views=views, commands=commands)


def _scan_quoted(cmd: str, start: int, quote: str, escapes: bool) -> tuple[int, list[str]]:
    """Return (index of the closing quote, code from $(...) / `...` inside double quotes)."""
    j, n = start, len(cmd)
    substitutions: list[str] = []
    while j < n and cmd[j] != quote:
        if escapes and cmd[j] == "\\":
            j += 2
            continue
        if quote == '"' and cmd.startswith("$(", j) and not cmd.startswith("$((", j):
            end = _skip_substitution(cmd, j)
            substitutions.append(cmd[j + 2:end - 1])
            j = end
            continue
        if quote == '"' and cmd[j] == "`":
            end = cmd.find("`", j + 1)
            end = n if end < 0 else end
            substitutions.append(cmd[j + 1:end])
            j = end + 1
            continue
        j += 1
    return min(j, n), substitutions


def _skip_substitution(cmd: str, i: int) -> int:
    """Given cmd[i:i+2] == "$(", return the index just past its matching ")".

    Understands nested quotes and heredocs, which is what makes the ubiquitous
    git commit -m "$(cat <<'EOF' ... EOF)" form parse correctly even when the
    message body contains quotes or parentheses.
    """
    depth, j, n = 1, i + 2, len(cmd)
    pending: list[tuple[str, bool]] = []
    while j < n:
        c = cmd[j]
        if c == "\\":
            j += 2
            continue
        if c == "'":
            k = cmd.find("'", j + 1)
            j = n if k < 0 else k + 1
            continue
        if c == '"':
            j = _scan_quoted(cmd, j + 1, '"', escapes=True)[0] + 1
            continue
        if cmd.startswith("<<", j) and not cmd.startswith("<<<", j):
            m = _HEREDOC.match(cmd, j)
            if m:
                pending.append((m.group(3), m.group(1) == "-"))
                j = m.end()
                continue
        if c == "\n" and pending:
            j = _consume_heredocs(cmd, j + 1, [(d, s, False) for d, s in pending], [])
            pending.clear()
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n


def _consume_heredocs(cmd: str, i: int, heredocs: list[tuple[str, bool, bool]], nested: list[str]) -> int:
    n = len(cmd)
    for delimiter, strip_tabs, is_code in heredocs:
        body: list[str] = []
        while i < n:
            e = cmd.find("\n", i)
            line = cmd[i:] if e < 0 else cmd[i:e]
            i = n if e < 0 else e + 1
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                break
            body.append(line)
        if is_code:
            nested.append("\n".join(body))
    return i


def _is_code_argument(words: list[str]) -> bool:
    """Is the quoted string about to be read code a shell will run?"""
    if not words:
        return False
    names = [os.path.basename(w) for w in words]
    if "eval" in names:
        return True
    if _to_command(words).name == "ssh":
        return True
    return bool(re.fullmatch(r"-[A-Za-z]*c", words[-1])) and any(n in SHELLS for n in names)


def _feeds_a_shell(words: list[str]) -> bool:
    return any(os.path.basename(w) in SHELLS for w in words) or _to_command(words).name == "ssh"


def _to_command(raw: list[str]) -> Command:
    words: list[str] = []
    outs: list[str] = []
    ins: list[str] = []
    k = 0
    while k < len(raw):
        w = raw[k]
        if w.startswith("<<<"):
            k += 2 if w == "<<<" else 1
            continue
        m = _REDIRECT.fullmatch(w)
        if m:
            op, target = m.group(1), m.group(2)
            if not target and k + 1 < len(raw):
                k += 1
                target = raw[k]
            if target and not target.startswith("&"):
                (ins if op == "<" else outs).append(target)
            k += 1
            continue
        words.append(w)
        k += 1
    return Command(words=words, out_targets=outs, in_targets=ins)
