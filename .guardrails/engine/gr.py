#!/usr/bin/env python3
"""guardrails CLI - one engine behind the Claude Code hooks, the pre-commit hook and CI.

  gr check [--staged | --changed | --all] [PATH...]   run the file rules (exit 1 on violations)
  gr hook pre-tool|post-tool|stop|session-start        Claude Code hook entry point (JSON on stdin)
  gr test                                              every rule must catch its own bad examples
  gr list | gr explain ID | gr context                 what is enforced, and why
  gr baseline                                          grandfather today's violations (humans only)
  gr setup                                             wire the git pre-commit hook in this clone
  gr doctor                                            verify every layer is actually wired

Run through the .guardrails/gr launcher, which finds a Python 3.11+.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep .guardrails/engine free of __pycache__ churn
ENGINE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ENGINE_DIR))

import gr_git  # noqa: E402
from gr_config import ConfigError, find_root, load  # noqa: E402
from gr_hooks import HOOK_MARKER, UNLOCK_ENV, handle, precommit_wired, session_context  # noqa: E402
from gr_report import explain, github_annotations, render  # noqa: E402
from gr_rules import baseline_from, collect, example_hits  # noqa: E402

VERSION = "0.1.0"


def _root(args: argparse.Namespace) -> Path:
    if args.root:
        return Path(args.root).resolve()
    # The engine is vendored at <repo>/.guardrails/engine/, which pins the repo it guards.
    if ENGINE_DIR.parent.name == ".guardrails":
        return ENGINE_DIR.parent.parent
    found = find_root(Path.cwd())
    if found is None:
        raise ConfigError("no .guardrails/guardrails.toml here or in any parent directory")
    return found


def cmd_check(args: argparse.Namespace) -> int:
    cfg = load(_root(args))
    mode = "staged" if args.staged else "changed" if args.changed else "all"
    violations = collect(cfg, mode, args.paths or None)
    if not violations:
        if not args.quiet:
            print(f"guardrails: {mode if not args.paths else 'paths'} clean ({len(cfg.rules)} rules)")
        return 0
    audience = args.format or ("claude" if os.environ.get("CLAUDECODE") == "1" else "human")
    headline = {"staged": "Commit blocked by guardrails:", "changed": "Uncommitted changes break guardrails:"}
    sys.stderr.write(render(violations, audience, headline.get(mode, "Guardrail violations:")) + "\n")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(github_annotations(violations))
    return 1


def cmd_hook(args: argparse.Namespace) -> int:
    # Fail open with a visible message: a broken guardrail must not brick every tool call,
    # and CI + pre-commit still stand behind it. Exit 1 is non-blocking but shown to the user.
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
        cfg = load(_root(args))
        return handle(args.event, cfg, data)
    except ConfigError as e:
        sys.stderr.write(f"guardrails OFF - config error: {e}\n")
        return 1
    except Exception as e:  # see comment above
        sys.stderr.write(f"guardrails OFF - internal error ({type(e).__name__}: {e}); please report it\n")
        return 1


def cmd_test(args: argparse.Namespace) -> int:
    cfg = load(_root(args))
    failures, checked, untested = [], 0, []
    for rule in cfg.rules:
        if rule.regex is not None and not rule.bad and rule.kind != "source_of_truth":
            untested.append(rule.id)
        for example in rule.bad:
            checked += 1
            if not example_hits(cfg, rule, example):
                failures.append(f"{rule.id}: should catch, but allows:  {example}")
        for example in rule.good:
            checked += 1
            if example_hits(cfg, rule, example):
                failures.append(f"{rule.id}: should allow, but catches:  {example}")
    for f in failures:
        print(f"FAIL {f}", file=sys.stderr)
    if untested:
        print(f"note: no `bad` examples (untested): {', '.join(untested)}", file=sys.stderr)
    print(f"guardrails: {checked - len(failures)}/{checked} rule examples behave as declared "
          f"across {len(cfg.rules)} rules")
    return 1 if failures else 0


def cmd_list(args: argparse.Namespace) -> int:
    cfg = load(_root(args))
    by_kind: dict[str, list] = {}
    for r in cfg.rules:
        by_kind.setdefault(r.kind, []).append(r)
    for kind, rules in by_kind.items():
        print(f"\n{kind}")
        for r in rules:
            flag = " (ask)" if r.action == "ask" else ""
            print(f"  {r.id:<34}{flag:<7}[{r.origin}]")
    print(f"\n{len(cfg.rules)} rules from: {', '.join(dict.fromkeys(r.origin for r in cfg.rules))}")
    print(f"protected branches: {', '.join(cfg.protected_branches()) or '-'}   "
          f"ask in bypass mode: {cfg.settings['bypass_ask']}")
    return 0


def cmd_explain(args: argparse.Namespace) -> int:
    cfg = load(_root(args))
    rule = cfg.get(args.rule_id)
    if rule is None:
        print(f"no rule '{args.rule_id}' - see `gr list`", file=sys.stderr)
        return 1
    print(explain(rule))
    return 0


def cmd_context(args: argparse.Namespace) -> int:
    print(session_context(load(_root(args))))
    return 0


def cmd_baseline(args: argparse.Namespace) -> int:
    if os.environ.get("CLAUDECODE") == "1" and os.environ.get(UNLOCK_ENV) != "1":
        print("guardrails: refusing - grandfathering violations is a human decision. Ask the user to run\n"
              "`.guardrails/gr baseline` themselves (or prefix it with `!` in Claude Code).", file=sys.stderr)
        return 2
    root = _root(args)
    cfg = load(root)
    cfg.baseline = {}
    data = baseline_from(collect(cfg, "all"))
    path = cfg.gdir / "baseline.json"
    doc = {"_comment": "Pre-existing violations, grandfathered by `gr baseline`. Counts may only go down: "
                       "fix debt and re-run to shrink this file. Never hand-edit to make a check pass."}
    path.write_text(json.dumps({**doc, **data}, indent=2) + "\n")
    total = sum(len(v) for v in data.values())
    print(f"guardrails: baseline written to {path.relative_to(root)} ({total} file/rule entries). Commit it.")
    return 0


def cmd_setup(args: argparse.Namespace) -> int:
    cfg = load(_root(args))
    if not gr_git.is_repo(cfg.root):
        print("guardrails: not a git repository - nothing to wire")
        return 0
    if precommit_wired(cfg):
        print("guardrails: pre-commit hook already wired")
        return 0
    hook = cfg.root / ".githooks" / "pre-commit"
    if hook.is_file() and HOOK_MARKER in hook.read_text(errors="replace"):
        current = gr_git.config_get(cfg.root, "core.hooksPath")
        if current and current != ".githooks":
            print(f"guardrails: core.hooksPath is '{current}', not .githooks - add the guardrails block to "
                  f"{current}/pre-commit (re-running install.py does this)", file=sys.stderr)
            return 1
        gr_git.config_set(cfg.root, "core.hooksPath", ".githooks")
        print("guardrails: git core.hooksPath -> .githooks (pre-commit guardrails active)")
        return 0
    print("guardrails: no pre-commit hook carrying the guardrails block found - re-run install.py",
          file=sys.stderr)
    return 1


def cmd_doctor(args: argparse.Namespace) -> int:
    root = _root(args)
    problems = 0

    def report(ok: bool, text: str, hint: str = "") -> None:
        nonlocal problems
        problems += 0 if ok else 1
        print(f"  {'ok ' if ok else 'XX '} {text}" + (f"\n       -> {hint}" if hint and not ok else ""))

    print(f"guardrails {VERSION} - {root}")
    report(sys.version_info >= (3, 11), f"python {sys.version.split()[0]}", "needs Python 3.11+")
    try:
        cfg = load(root)
        report(True, f"config loads: {len(cfg.rules)} rules")
    except ConfigError as e:
        report(False, f"config: {e}")
        return 1
    launcher = cfg.gdir / "gr"
    report(os.access(launcher, os.X_OK), ".guardrails/gr launcher is executable", f"chmod +x {launcher}")
    if gr_git.is_repo(root):
        report(precommit_wired(cfg), "git pre-commit hook runs guardrails", "run .guardrails/gr setup")
        for probe in (".env", ".env.local", "id_rsa", "release.keystore", "key.pem"):
            report(gr_git.is_ignored(root, probe), f"{probe} would be gitignored",
                   "add secret file patterns to .gitignore (install.py does this)")
    else:
        report(False, "git repository", "git init - the pre-commit layer needs git")
    settings = root / ".claude" / "settings.json"
    try:
        hooks = json.loads(settings.read_text()).get("hooks", {})
    except (OSError, json.JSONDecodeError):
        hooks = {}
    for event in ("SessionStart", "PreToolUse", "PostToolUse", "Stop"):
        commands = [h.get("command", "") for entry in hooks.get(event, []) for h in entry.get("hooks", [])]
        wired = any(".guardrails/gr" in c and " hook " in c for c in commands)
        report(wired, f"Claude Code {event} hook wired in .claude/settings.json", "re-run install.py")
    ci = root / ".github" / "workflows" / "guardrails.yml"
    report(ci.is_file(), "CI workflow .github/workflows/guardrails.yml", "re-run install.py (or add your own CI step)")
    print("\nall layers wired" if problems == 0 else f"\n{problems} problem(s)")
    return 0 if problems == 0 else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gr", description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--root", help="repo root (default: the repo this engine is vendored into)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("check", help="run file rules")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--staged", action="store_true", help="files staged for commit (pre-commit)")
    group.add_argument("--changed", action="store_true", help="uncommitted + untracked files")
    group.add_argument("--all", action="store_true", help="every tracked file (default; CI)")
    p.add_argument("--format", choices=("human", "claude"))
    p.add_argument("-q", "--quiet", action="store_true")
    p.add_argument("paths", nargs="*")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("hook", help="Claude Code hook entry point")
    p.add_argument("event", choices=("pre-tool", "post-tool", "stop", "session-start"))
    p.set_defaults(func=cmd_hook)

    for name, func, text in (("test", cmd_test, "self-test rules against their examples"),
                             ("list", cmd_list, "list active rules"),
                             ("context", cmd_context, "print the session-start context"),
                             ("baseline", cmd_baseline, "grandfather current violations"),
                             ("setup", cmd_setup, "wire the pre-commit hook in this clone"),
                             ("doctor", cmd_doctor, "verify every layer is wired")):
        sub.add_parser(name, help=text).set_defaults(func=func)
    p = sub.add_parser("explain", help="why/fix and patterns for one rule")
    p.add_argument("rule_id")
    p.set_defaults(func=cmd_explain)
    sub.add_parser("version").set_defaults(func=lambda a: print(VERSION) or 0)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ConfigError as e:
        print(f"guardrails: config error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
