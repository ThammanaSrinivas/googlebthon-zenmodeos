"""Turns Violations into micro-context: what fired, where, why it matters, how to fix it.

Two audiences, one shape:
  claude  Hook output. Plain text, no colour, ends with the protocol for what to do
          next, because this text is injected straight into Claude's context.
  human   Pre-commit / CLI. Colour on a TTY; on GitHub Actions also emits
          ::error annotations so the same why/fix lands inline on the PR diff.
"""

from __future__ import annotations

import os
import sys
from collections import OrderedDict

from gr_rules import Violation

MAX_LOCATIONS = 12

CLAUDE_FOOTER = (
    "These are guardrails, not suggestions. Apply each \"fix\" and continue; don't retry the same thing\n"
    "reworded. Never edit .guardrails/, git hooks or .claude/settings*.json, never add suppressions,\n"
    "never bypass hooks. If a rule is wrong for this case, stop and tell the user the rule id\n"
    "(details: .guardrails/gr explain <id>) - changing a guardrail is the user's decision."
)
HUMAN_FOOTER = (
    "Explain a rule: .guardrails/gr explain <id>   ·   grandfather existing debt: .guardrails/gr baseline"
)


def _style(code: str, text: str, color: bool) -> str:
    return f"\033[{code}m{text}\033[0m" if color else text


def _location(v: Violation) -> str:
    where = v.path + (f":{v.line}" if v.line else "")
    parts = [p for p in (where, v.found) if p]
    text = "  ".join(parts)
    return text + (f"  ({v.note})" if v.note else "")


def render(violations: list[Violation], audience: str = "claude", headline: str = "",
           color: bool | None = None) -> str:
    if color is None:
        color = audience == "human" and sys.stderr.isatty() and not os.environ.get("NO_COLOR")
    groups: OrderedDict[str, list[Violation]] = OrderedDict()
    for v in violations:
        groups.setdefault(v.rule.id, []).append(v)
    lines: list[str] = []
    if headline:
        lines += [headline, ""]
    for rule_id, group in groups.items():
        rule = group[0].rule
        if rule.kind in ("command", "git_push_branch", "protect_path", "read_protect") and len(group) == 1:
            count = "needs the user's OK" if rule.action == "ask" else "blocked"
        else:
            count = f"{len(group)} violation{'s' if len(group) > 1 else ''}"
        lines.append(_style("1;31", f"GUARDRAIL [{rule_id}]", color) + f" {count}")
        for v in group[:MAX_LOCATIONS]:
            loc = _location(v)
            if loc:
                lines.append(f"  {loc}")
        if len(group) > MAX_LOCATIONS:
            lines.append(f"  … and {len(group) - MAX_LOCATIONS} more")
        lines.append(_style("2", "  why: ", color) + rule.why)
        lines.append(_style("1;32", "  fix: ", color) + rule.fix)
        if rule.ref:
            lines.append(_style("2", "  ref: ", color) + rule.ref)
        lines.append("")
    lines.append(CLAUDE_FOOTER if audience == "claude" else HUMAN_FOOTER)
    return "\n".join(lines)


def github_annotations(violations: list[Violation]) -> str:
    def esc(s: str) -> str:
        return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    out = []
    for v in violations:
        loc = f" file={v.path}" + (f",line={v.line}" if v.line else "") if v.path else ""
        out.append(f"::error{loc},title=guardrail {v.rule.id}::{esc(v.found + ' - ' + v.rule.fix)}")
    return "\n".join(out)


def explain(rule) -> str:
    lines = [f"{rule.id}  ({rule.kind}, from {rule.origin}, action: {rule.action})", "",
             f"why: {rule.why}", f"fix: {rule.fix}"]
    if rule.ref:
        lines.append(f"ref: {rule.ref}")
    if rule.regex is not None:
        lines += ["", f"regex: {rule.regex.pattern}" + (f"   (scope: {rule.scope})" if rule.kind == "command" else "")]
    for label, values in (("paths", rule.paths), ("exclude", rule.exclude), ("tags", rule.tags),
                          ("branches", rule.branches)):
        if values:
            lines.append(f"{label}: {', '.join(values)}")
    if rule.kind == "duplicate_literal":
        lines.append(f"max: {rule.max} copies of any literal of {rule.min_length}+ characters")
    elif rule.max:
        lines.append(f"max: {rule.max} lines")
    if rule.max_kb:
        lines.append(f"max: {rule.max_kb} KB")
    if rule.source:
        lines.append(f"source of truth: {rule.source}")
    for label, values in (("catches", rule.bad), ("allows", rule.good)):
        if values:
            lines += ["", f"{label}:"] + [f"  {v}" for v in values]
    return "\n".join(lines)
