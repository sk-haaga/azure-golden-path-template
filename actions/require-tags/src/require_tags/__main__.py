"""Command-line entry point, used both by the Docker action and locally.

    python -m require_tags --plan-json plan.json --required-tags owner,service

Inside GitHub Actions it also writes error annotations, a job summary table and
step outputs (``passed``, ``violations``, ``warnings``, ``checked``).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import uuid
from pathlib import Path

from require_tags import __version__
from require_tags.checker import (
    DEFAULT_ACTIONS,
    DEFAULT_REQUIRED_TAGS,
    Config,
    PlanError,
    Report,
    check_plan,
    parse_allowed_values,
    parse_list,
)


def _truthy(value: str | None) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="require-tags", description=__doc__)
    p.add_argument("--plan-json", required=True, help="Output of `terraform show -json`")
    p.add_argument("--required-tags", default=",".join(DEFAULT_REQUIRED_TAGS))
    p.add_argument("--allowed-values", default="", help="Lines of key=value1|value2")
    p.add_argument("--ignore-resource-types", default="")
    p.add_argument("--ignore-addresses", default="", help="Glob patterns, e.g. module.legacy.*")
    p.add_argument("--actions", default=",".join(DEFAULT_ACTIONS))
    p.add_argument("--tag-attribute", default="tags")
    p.add_argument("--fail-on-unknown", default="false")
    p.add_argument("--report-path", default="", help="Optional path for a JSON report")
    p.add_argument("--version", action="version", version=__version__)
    return p


def _escape(value: str) -> str:
    """Escape data for a GitHub workflow command."""
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def emit_annotations(report: Report) -> None:
    for f in report.errors:
        print(
            f"::error title=require-tags: {f.kind} tag '{f.tag}'::{_escape(f.address)}: "
            f"{_escape(f.detail)}"
        )
    for f in report.warnings:
        print(
            f"::warning title=require-tags: tag '{f.tag}' not verifiable::"
            f"{_escape(f.address)}: {_escape(f.detail)}"
        )


def render_summary(report: Report, required: tuple[str, ...]) -> str:
    status = "✅ Passed" if report.passed else "❌ Blocked"
    lines = [
        f"## Required tags check: {status}",
        "",
        f"Required tags: {', '.join(f'`{t}`' for t in required)}",
        "",
        f"- Resources checked: **{len(report.checked)}**",
        f"- Violations: **{len(report.errors)}**",
        f"- Warnings (unknown until apply): **{len(report.warnings)}**",
    ]
    if report.skipped:
        lines.append(f"- Skipped by ignore rules: {len(report.skipped)}")
    rows = [(f, "error") for f in report.errors] + [(f, "warning") for f in report.warnings]
    if rows:
        lines += ["", "| Resource | Tag | Problem | Level |", "|---|---|---|---|"]
        for f, level in rows:
            detail = f.detail.replace("|", "\\|")
            lines.append(f"| `{f.address}` | `{f.tag}` | {f.kind}: {detail} | {level} |")
    if not report.passed:
        lines += [
            "",
            "Add the missing tags in `golden-path.yaml` (or the resource's `tags` block) "
            "and push again. The deployment will not run until this check passes.",
        ]
    return "\n".join(lines) + "\n"


def _append(path_env: str, text: str) -> None:
    path = os.environ.get(path_env)
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(text)


def write_outputs(report: Report, report_json: str) -> None:
    delimiter = f"EOF_{uuid.uuid4().hex}"
    _append(
        "GITHUB_OUTPUT",
        f"passed={str(report.passed).lower()}\n"
        f"violations={len(report.errors)}\n"
        f"warnings={len(report.warnings)}\n"
        f"checked={len(report.checked)}\n"
        f"report<<{delimiter}\n{report_json}\n{delimiter}\n",
    )


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        cfg = Config(
            required_tags=parse_list(args.required_tags) or DEFAULT_REQUIRED_TAGS,
            allowed_values=parse_allowed_values(args.allowed_values),
            ignore_resource_types=parse_list(args.ignore_resource_types),
            ignore_addresses=parse_list(args.ignore_addresses),
            actions=parse_list(args.actions) or DEFAULT_ACTIONS,
            tag_attribute=args.tag_attribute.strip() or "tags",
            fail_on_unknown=_truthy(args.fail_on_unknown),
        )
        plan_path = Path(args.plan_json)
        if not plan_path.is_file():
            raise PlanError(f"Plan file not found: {plan_path}")
        try:
            plan = json.loads(plan_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise PlanError(f"Plan file is not valid JSON: {exc}") from exc
        report = check_plan(plan, cfg)
    except (PlanError, ValueError) as exc:
        print(f"::error title=require-tags::{_escape(str(exc))}")
        return 2

    report_json = json.dumps(report.to_dict(), indent=2)
    emit_annotations(report)
    summary = render_summary(report, cfg.required_tags)
    _append("GITHUB_STEP_SUMMARY", summary)
    write_outputs(report, report_json)
    if args.report_path:
        Path(args.report_path).write_text(report_json + "\n", encoding="utf-8")

    print(summary)
    return 0 if report.passed else 1


if __name__ == "__main__":
    sys.exit(main())
