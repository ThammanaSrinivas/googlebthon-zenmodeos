"""Loads .guardrails/guardrails.toml plus the presets it extends into one Config.

Layering, first to last: each preset named in `extends`, then the project file.
- [[rule]]       a later layer's rule with the same id replaces the earlier one.
- [override.ID]  per-key changes to an inherited rule; `extra_<key>` appends to a list.
- disable        drops inherited rules by id.
- [settings]     list settings accumulate across layers (use "!x" to take one back
                 out); scalar settings: the last layer wins.
- [defaults.K]   default fields for every rule of kind K (e.g. one why/fix shared by
                 all secret patterns).

Every rule must end up with `why` and `fix`: that text is the micro-context Claude
reads at the moment it is blocked, so a rule without it is rejected at load time.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - exercised only on old Pythons
    sys.stderr.write("guardrails: Python 3.11+ is required (tomllib missing).\n")
    raise SystemExit(1) from None

KIND_FIELDS: dict[str, tuple[str, ...]] = {
    "command": ("regex",),
    "git_push_branch": (),
    "protect_path": ("paths",),
    "read_protect": ("paths",),
    "secret": ("regex",),
    "content": ("regex", "paths"),
    "source_of_truth": ("source", "extract", "paths"),
    "duplicate_literal": ("paths",),
    "max_lines": ("paths", "max"),
    "required_tags": ("paths", "tags"),
    "forbidden_file": ("paths",),
    "max_file_size": ("max_kb",),
}
LIST_SETTINGS = ("exclude", "secret_files", "protected_branches")
SCALAR_SETTINGS = {"bypass_ask": "block", "session_context": True, "stop_check": True}
RULE_ID = re.compile(r"[a-z0-9][a-z0-9-]*")
SPLIT_MARKER = "{{}}"  # lets preset examples hold secret-shaped strings without being secrets
DUPLICATE_COPIES = 2       # duplicate_literal: copies of one text allowed before the next fails
DUPLICATE_MIN_LENGTH = 12  # duplicate_literal: shorter literals are keys and labels, not prose


class ConfigError(Exception):
    pass


@dataclass
class Rule:
    id: str
    kind: str
    why: str
    fix: str
    origin: str
    ref: str = ""
    action: str = "block"
    scope: str = "unquoted"
    stage: str = "post"
    regex: re.Pattern[str] | None = None
    paths: list[str] = field(default_factory=list)
    exclude: list[str] = field(default_factory=list)
    branches: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    max: int = 0
    max_kb: int = 0
    min_length: int = 0
    source: str = ""
    extract: re.Pattern[str] | None = None
    bad: list[str] = field(default_factory=list)
    good: list[str] = field(default_factory=list)


@dataclass
class Config:
    root: Path
    rules: list[Rule]
    settings: dict
    baseline: dict[str, dict[str, int]]

    @property
    def gdir(self) -> Path:
        return self.root / ".guardrails"

    def of(self, *kinds: str) -> list[Rule]:
        return [r for r in self.rules if r.kind in kinds]

    def get(self, rule_id: str) -> Rule | None:
        return next((r for r in self.rules if r.id == rule_id), None)

    def protected_branches(self) -> list[str]:
        out: list[str] = []
        for b in self.settings["protected_branches"]:
            if b.startswith("!"):
                out = [x for x in out if x != b[1:]]
            elif b not in out:
                out.append(b)
        return out


def find_root(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        if (p / ".guardrails" / "guardrails.toml").is_file():
            return p
    return None


def _read_toml(path: Path) -> dict:
    try:
        with path.open("rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        raise ConfigError(f"missing {path}") from None
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"{path}: {e}") from None


def load(root: Path) -> Config:
    gdir = root / ".guardrails"
    project = _read_toml(gdir / "guardrails.toml")
    layers: list[tuple[str, dict]] = []
    for name in project.get("extends", ["base"]):
        layers.append((name, _read_toml(gdir / "presets" / f"{name}.toml")))
    layers.append(("project", project))

    settings: dict = dict(SCALAR_SETTINGS)
    settings.update({k: [] for k in LIST_SETTINGS})
    defaults: dict[str, dict] = {}
    raw_rules: dict[str, dict] = {}
    for name, data in layers:
        for key, value in data.get("settings", {}).items():
            if key in LIST_SETTINGS:
                settings[key] = settings[key] + list(value)
            elif key in SCALAR_SETTINGS:
                settings[key] = value
            else:
                raise ConfigError(f"{name}: unknown setting '{key}'")
        for kind, values in data.get("defaults", {}).items():
            defaults.setdefault(kind, {}).update(values)
        for r in data.get("rule", []):
            if "id" not in r:
                raise ConfigError(f"{name}: a [[rule]] has no id")
            raw_rules[r["id"]] = {**r, "_origin": name}

    for rule_id, changes in project.get("override", {}).items():
        if rule_id not in raw_rules:
            raise ConfigError(f"project: [override.{rule_id}] names a rule that doesn't exist")
        for key, value in changes.items():
            if key.startswith("extra_"):
                base_key = key[len("extra_"):]
                raw_rules[rule_id][base_key] = list(raw_rules[rule_id].get(base_key, [])) + list(value)
            else:
                raw_rules[rule_id][key] = value
    for rule_id in project.get("disable", []):
        if raw_rules.pop(rule_id, None) is None:
            raise ConfigError(f"project: disable lists unknown rule '{rule_id}'")

    rules = [_build(r, defaults.get(r.get("kind", ""), {})) for r in raw_rules.values()]
    settings["bypass_ask"] = str(settings["bypass_ask"])
    if settings["bypass_ask"] not in ("block", "ask"):
        raise ConfigError("settings.bypass_ask must be \"block\" or \"ask\"")
    return Config(root=root, rules=rules, settings=settings, baseline=load_baseline(gdir))


def _compile(rule_id: str, key: str, pattern: str) -> re.Pattern[str]:
    try:
        return re.compile(pattern, re.MULTILINE)
    except re.error as e:
        raise ConfigError(f"rule '{rule_id}': invalid {key} pattern: {e}") from None


def _build(raw: dict, kind_defaults: dict) -> Rule:
    data = {**kind_defaults, **raw}
    rule_id, kind, origin = data["id"], data.get("kind", ""), data.pop("_origin")
    where = f"rule '{rule_id}' ({origin})"
    if not RULE_ID.fullmatch(rule_id):
        raise ConfigError(f"{where}: ids are lowercase-kebab-case")
    if kind not in KIND_FIELDS:
        raise ConfigError(f"{where}: unknown kind '{kind}' (one of: {', '.join(KIND_FIELDS)})")
    for key in ("why", "fix", *KIND_FIELDS[kind]):
        if not data.get(key):
            raise ConfigError(f"{where}: missing '{key}'" + (
                " - every rule needs why/fix micro-context, it is what Claude reads when blocked"
                if key in ("why", "fix") else ""))
    duplicates = kind == "duplicate_literal"
    rule = Rule(id=rule_id, kind=kind, why=data["why"].strip(), fix=data["fix"].strip(), origin=origin,
                ref=data.get("ref", ""), action=data.get("action", "block"), scope=data.get("scope", "unquoted"),
                stage=data.get("stage", "pre" if kind == "secret" else "post"),
                paths=list(data.get("paths", ["**"] if kind == "secret" else [])),
                exclude=list(data.get("exclude", [])), branches=list(data.get("branches", [])),
                tags=list(data.get("tags", [])), max=int(data.get("max", DUPLICATE_COPIES if duplicates else 0)),
                max_kb=int(data.get("max_kb", 0)), source=data.get("source", ""),
                min_length=int(data.get("min_length", DUPLICATE_MIN_LENGTH if duplicates else 0)),
                bad=[s.replace(SPLIT_MARKER, "") for s in data.get("bad", [])],
                good=[s.replace(SPLIT_MARKER, "") for s in data.get("good", [])])
    if rule.action not in ("block", "ask"):
        raise ConfigError(f"{where}: action must be \"block\" or \"ask\"")
    if rule.scope not in ("unquoted", "raw"):
        raise ConfigError(f"{where}: scope must be \"unquoted\" or \"raw\"")
    if rule.stage not in ("pre", "post"):
        raise ConfigError(f"{where}: stage must be \"pre\" or \"post\"")
    if duplicates and (rule.max < 1 or rule.min_length < 1):
        raise ConfigError(f"{where}: max (copies allowed) and min_length must be at least 1")
    if "regex" in data:
        rule.regex = _compile(rule_id, "regex", data["regex"])
    if "extract" in data:
        rule.extract = _compile(rule_id, "extract", data["extract"])
        if rule.extract.groups < 1:
            raise ConfigError(f"{where}: extract needs one capture group (the literal)")
    known = {"id", "kind", "why", "fix", "ref", "action", "scope", "stage", "regex", "paths", "exclude",
             "branches", "tags", "max", "max_kb", "min_length", "source", "extract", "bad", "good"}
    unknown = set(data) - known
    if unknown:
        raise ConfigError(f"{where}: unknown field(s) {', '.join(sorted(unknown))}")
    return rule


def load_baseline(gdir: Path) -> dict[str, dict[str, int]]:
    path = gdir / "baseline.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path}: {e}") from None
    return {k: v for k, v in data.items() if not k.startswith("_")}
