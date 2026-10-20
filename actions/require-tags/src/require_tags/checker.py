"""Core logic: find resources in a Terraform plan that are missing required tags.

The input is the JSON produced by ``terraform show -json <planfile>``. For every
managed resource that the plan will create or update (configurable), we look at
the planned ``tags`` attribute and report:

* missing   - a required tag is absent or has an empty value
* invalid   - a tag value is not in the allowed list for that key
* unknown   - the value is only known after apply, so it cannot be verified

Resource types that have no ``tags`` attribute at all (role assignments, for
example) are skipped automatically, because the attribute never appears in the
plan for them. Azure treats tag names case-insensitively, so matching here is
case-insensitive too.
"""

from __future__ import annotations

import fnmatch
from dataclasses import dataclass, field
from typing import Any

DEFAULT_REQUIRED_TAGS = ("owner", "cost-center", "environment", "service", "data-classification")
DEFAULT_ACTIONS = ("create", "update")


@dataclass(frozen=True)
class Finding:
    address: str
    resource_type: str
    kind: str  # "missing" | "invalid" | "unknown"
    tag: str
    detail: str


@dataclass
class Config:
    required_tags: tuple[str, ...] = DEFAULT_REQUIRED_TAGS
    allowed_values: dict[str, tuple[str, ...]] = field(default_factory=dict)
    ignore_resource_types: tuple[str, ...] = ()
    ignore_addresses: tuple[str, ...] = ()
    actions: tuple[str, ...] = DEFAULT_ACTIONS
    tag_attribute: str = "tags"
    fail_on_unknown: bool = False


@dataclass
class Report:
    checked: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    findings: list[Finding] = field(default_factory=list)
    fail_on_unknown: bool = False

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.kind != "unknown" or self.fail_on_unknown]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.kind == "unknown" and not self.fail_on_unknown]

    @property
    def passed(self) -> bool:
        return not self.errors

    def to_dict(self) -> dict[str, Any]:
        return {
            "passed": self.passed,
            "checked": len(self.checked),
            "skipped": len(self.skipped),
            "errors": [f.__dict__ for f in self.errors],
            "warnings": [f.__dict__ for f in self.warnings],
        }


class PlanError(ValueError):
    """The file is not a usable Terraform JSON plan."""


def parse_list(raw: str | None) -> tuple[str, ...]:
    """Split a comma- or newline-separated action input into clean items."""
    if not raw:
        return ()
    items = [part.strip() for line in raw.splitlines() for part in line.split(",")]
    return tuple(i for i in items if i and not i.startswith("#"))


def parse_allowed_values(raw: str | None) -> dict[str, tuple[str, ...]]:
    """Parse lines like ``environment=staging|production`` into a dict."""
    result: dict[str, tuple[str, ...]] = {}
    if not raw:
        return result
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"allowed-values line must look like key=a|b, got: {line!r}")
        key, values = line.split("=", 1)
        allowed = tuple(v.strip() for v in values.split("|") if v.strip())
        if not key.strip() or not allowed:
            raise ValueError(f"allowed-values line has an empty key or no values: {line!r}")
        result[key.strip().lower()] = allowed
    return result


def _is_ignored(address: str, rtype: str, cfg: Config) -> bool:
    if rtype in cfg.ignore_resource_types:
        return True
    return any(fnmatch.fnmatchcase(address, pattern) for pattern in cfg.ignore_addresses)


def check_plan(plan: dict[str, Any], cfg: Config) -> Report:
    looks_like_plan = isinstance(plan, dict) and (
        "resource_changes" in plan or "format_version" in plan
    )
    if not looks_like_plan:
        raise PlanError("Input does not look like `terraform show -json` output")

    report = Report(fail_on_unknown=cfg.fail_on_unknown)
    attr = cfg.tag_attribute

    for rc in plan.get("resource_changes") or []:
        if rc.get("mode", "managed") != "managed":
            continue
        address = rc.get("address", "<unknown>")
        rtype = rc.get("type", "")
        change = rc.get("change") or {}
        actions = change.get("actions") or []

        if not any(a in cfg.actions for a in actions):
            continue
        if _is_ignored(address, rtype, cfg):
            report.skipped.append(address)
            continue

        after = change.get("after") or {}
        after_unknown = change.get("after_unknown") or {}

        # Not a taggable resource type: the attribute is absent from the schema.
        if attr not in after and attr not in after_unknown:
            continue

        report.checked.append(address)
        unknown_spec = after_unknown.get(attr)

        if unknown_spec is True:
            for tag in cfg.required_tags:
                report.findings.append(
                    Finding(address, rtype, "unknown", tag, "tags are only known after apply")
                )
            continue

        tags = after.get(attr) or {}
        lowered = {str(k).lower(): v for k, v in tags.items()}
        unknown_keys = (
            {str(k).lower() for k, v in unknown_spec.items() if v is True}
            if isinstance(unknown_spec, dict)
            else set()
        )

        for tag in cfg.required_tags:
            key = tag.lower()
            if key in unknown_keys:
                report.findings.append(
                    Finding(address, rtype, "unknown", tag, "value is only known after apply")
                )
                continue
            value = lowered.get(key)
            if value is None or str(value).strip() == "":
                report.findings.append(
                    Finding(address, rtype, "missing", tag, "required tag is missing or empty")
                )
                continue
            allowed = cfg.allowed_values.get(key)
            if allowed and str(value) not in allowed:
                report.findings.append(
                    Finding(
                        address,
                        rtype,
                        "invalid",
                        tag,
                        f"value {value!r} is not one of: {', '.join(allowed)}",
                    )
                )

        # Allowed-values rules also apply to optional tags when they are present.
        for key, allowed in cfg.allowed_values.items():
            if key in {t.lower() for t in cfg.required_tags} or key in unknown_keys:
                continue
            value = lowered.get(key)
            if value is not None and str(value) not in allowed:
                report.findings.append(
                    Finding(
                        address,
                        rtype,
                        "invalid",
                        key,
                        f"value {value!r} is not one of: {', '.join(allowed)}",
                    )
                )

    return report
