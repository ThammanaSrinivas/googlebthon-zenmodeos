<!-- guardrails:begin - managed by guardrails install.py; edit .guardrails/guardrails.toml, not this block -->
## Guardrails

This repo enforces automated guardrails (`.guardrails/guardrails.toml`) in Claude Code hooks, the
git pre-commit hook and CI - one engine, one rule set. The active rules are injected at session
start; `.guardrails/gr list` and `.guardrails/gr explain <id>` show them.

- A `GUARDRAIL [id]` message is a hard stop that carries its own instructions: apply its **fix**
  and continue. Don't retry the same action reworded or look for another route to the same result.
- Never edit `.guardrails/`, git hooks or `.claude/settings*.json`, never add suppressions, never
  bypass hooks (`--no-verify`, `core.hooksPath`). Changing a guardrail is the user's decision.
- If a rule is wrong for the case at hand, stop and tell the user the rule id.
- Before you finish, `.guardrails/gr check --changed` must pass (the Stop hook enforces it).
<!-- guardrails:end -->
