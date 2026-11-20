"""Claude Code hook handlers. Each reads the hook's JSON from stdin, returns an exit code.

Contract (https://code.claude.com/docs/en/hooks):
  exit 2 + stderr  PreToolUse: the tool call is blocked and stderr is shown to Claude.
                   PostToolUse: the edit already happened; stderr is fed back so Claude
                   fixes it right away. Stop: Claude is sent back to work.
  JSON on stdout   PreToolUse "ask": the user is prompted, with our why/fix as the reason.
  exit 0           Nothing to say.

Rules with action = "ask" can't prompt anyone in bypassPermissions mode, so by default
(settings.bypass_ask = "block") they block there and tell Claude to get the user's OK
in words, with the user running the command themselves.
"""

from __future__ import annotations

import json
import os
import sys

import gr_git
from gr_config import Config
from gr_paths import resolve
from gr_report import CLAUDE_FOOTER, render
from gr_rules import Violation, apply_baseline, check_command, check_read, check_text, check_write, collect

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
UNLOCK_ENV = "GUARDRAILS_UNLOCK"
HOOK_MARKER = "guardrails:begin"


def handle(event: str, cfg: Config, data: dict) -> int:
    handler = {"pre-tool": _pre_tool, "post-tool": _post_tool, "stop": _stop,
               "session-start": _session_start}.get(event)
    if handler is None:
        sys.stderr.write(f"guardrails: unknown hook event '{event}'\n")
        return 1
    return handler(cfg, data)


def _tool(data: dict) -> tuple[str, dict, str]:
    return data.get("tool_name", ""), data.get("tool_input") or {}, data.get("cwd") or os.getcwd()


def _new_texts(tool: str, ti: dict) -> list[str]:
    if tool == "Write":
        return [ti.get("content", "")]
    if tool == "Edit":
        return [ti.get("new_string", "")]
    if tool == "MultiEdit":
        return [e.get("new_string", "") for e in ti.get("edits", [])]
    if tool == "NotebookEdit":
        return [ti.get("new_source", "")]
    return []


def _pre_tool(cfg: Config, data: dict) -> int:
    tool, ti, cwd = _tool(data)
    violations: list[Violation] = []
    if tool == "Bash" and ti.get("command"):
        violations = check_command(cfg, ti["command"], cwd)
    elif tool in EDIT_TOOLS:
        path = ti.get("file_path") or ti.get("notebook_path")
        if path:
            violations = check_write(cfg, path, _new_texts(tool, ti), cwd)
    elif tool == "Read" and ti.get("file_path"):
        violations = check_read(cfg, ti["file_path"], cwd)
    elif tool == "Grep" and ti.get("path"):
        violations = check_read(cfg, ti["path"], cwd)
    if os.environ.get(UNLOCK_ENV) == "1":
        violations = [v for v in violations if v.rule.kind != "protect_path"]
    if not violations:
        return 0

    bypass = data.get("permission_mode") == "bypassPermissions"
    escalate = bypass and cfg.settings["bypass_ask"] == "block"
    hard = any(v.rule.action == "block" for v in violations)
    if hard or escalate:
        text = render(violations)
        if escalate and not hard:  # only confirmations stand in the way: the user may run it
            shown = ti.get("command") or ti.get("file_path") or tool
            text = text.replace(CLAUDE_FOOTER, (
                "This needs the user's explicit OK, and bypass-permissions mode has no prompt to give it in.\n"
                f"Ask the user in words; if they agree, they run it themselves: ! {shown}\n\n") + CLAUDE_FOOTER)
        sys.stderr.write(text + "\n")
        return 2
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": render(violations).replace("\n" + CLAUDE_FOOTER, "").strip(),
    }}))
    return 0


def _post_tool(cfg: Config, data: dict) -> int:
    tool, ti, cwd = _tool(data)
    path = ti.get("file_path") or ti.get("notebook_path")
    if tool not in EDIT_TOOLS or not path:
        return 0
    rel, ab = resolve(str(cfg.root), path, cwd)
    if rel is None or not os.path.isfile(ab):
        return 0
    with open(ab, "rb") as f:
        data_bytes = f.read()
    if b"\0" in data_bytes[:8192]:
        return 0
    violations = apply_baseline(cfg, check_text(cfg, rel, data_bytes.decode("utf-8", "replace")))
    if not violations:
        return 0
    sys.stderr.write(render(violations, headline=(
        f"The edit to {rel} was applied, but the file now breaks {len({v.rule.id for v in violations})} "
        "guardrail(s). Fix it now, before moving on:")) + "\n")
    return 2


def _stop(cfg: Config, data: dict) -> int:
    if data.get("stop_hook_active") or not cfg.settings["stop_check"] or not gr_git.is_repo(cfg.root):
        return 0
    violations = collect(cfg, "changed")
    if not violations:
        return 0
    sys.stderr.write(render(violations, headline=(
        "Before you finish: uncommitted changes in this repo break these guardrails, so the pre-commit\n"
        "hook and CI will reject them. Fix the ones your work introduced. If one is in code you didn't\n"
        "touch, don't change it - mention it to the user in your summary instead.")) + "\n")
    return 2


def _session_start(cfg: Config, data: dict) -> int:
    if cfg.settings["session_context"]:
        print(session_context(cfg))
    return 0


def _first_sentence(text: str) -> str:
    text = " ".join(text.split())
    end = text.find(". ")
    return text if end < 0 else text[:end + 1]


def session_context(cfg: Config) -> str:
    """The rules up front, so Claude writes conforming code instead of learning by being blocked."""
    lines = ["GUARDRAILS are active in this repo (.guardrails/guardrails.toml). They run on every tool call,",
             "on commit and in CI. A blocked action comes back as a \"GUARDRAIL [id]\" message with why/fix.", ""]
    code_rules = cfg.of("content", "source_of_truth", "max_lines", "required_tags", "duplicate_literal")
    if code_rules:
        lines.append("Code rules (write code that already satisfies these):")
        for r in code_rules:
            scope = ", ".join(r.paths[:3]) + (", …" if len(r.paths) > 3 else "")
            limit = (f" ≤{r.max} lines." if r.kind == "max_lines" else
                     f" ≤{r.max} copies of any {r.min_length}+ char string." if r.kind == "duplicate_literal" else "")
            lines.append(f"- {r.id} [{scope}]:{limit} {_first_sentence(r.fix)}")
        lines.append("")
    for kinds, label in ((("command", "git_push_branch"), "Shell hard stops / confirmations"),
                         (("protect_path",), "Never edit"), (("read_protect",), "Never read")):
        rules = cfg.of(*kinds)
        if not rules:
            continue
        if kinds[0] == "command" or kinds[0] == "git_push_branch":
            lines.append(f"{label}: " + ", ".join(r.id + (" (ask)" if r.action == "ask" else "") for r in rules))
        else:
            paths = [p for r in rules for p in r.paths if not p.startswith("!")]
            lines.append(f"{label}: " + ", ".join(paths[:14]) + (", …" if len(paths) > 14 else ""))
    if cfg.of("secret"):
        lines.append("Secrets: never inline credentials in code or commands; read them from the environment.")
    if gr_git.is_repo(cfg.root) and not precommit_wired(cfg):
        lines += ["", "WARNING: the guardrails pre-commit hook isn't wired in this clone. Tell the user to run:",
                  "  .guardrails/gr setup"]
    lines += ["", CLAUDE_FOOTER]
    return "\n".join(lines)


def precommit_wired(cfg: Config) -> bool:
    hooks_path = gr_git.config_get(cfg.root, "core.hooksPath")
    if hooks_path.rstrip("/").endswith(".husky/_"):
        # husky v9: .husky/_/pre-commit is a generated proxy that runs .husky/pre-commit with sh,
        # so the user-level file needn't be executable.
        candidates = [(cfg.root / ".husky" / "pre-commit", False)]
    elif hooks_path:
        candidates = [(cfg.root / hooks_path / "pre-commit", True)]
    else:
        candidates = [(cfg.root / ".git" / "hooks" / "pre-commit", True)]
    for path, needs_exec in candidates:
        try:
            if (not needs_exec or os.access(path, os.X_OK)) and HOOK_MARKER in path.read_text(errors="replace"):
                return True
        except OSError:
            continue
    return False
