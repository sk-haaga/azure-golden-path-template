import json
from pathlib import Path

import pytest

from require_tags.checker import (
    Config,
    PlanError,
    check_plan,
    parse_allowed_values,
    parse_list,
)

FIXTURES = Path(__file__).parent / "fixtures"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def kinds(report) -> set[tuple[str, str, str]]:
    return {(f.address, f.tag, f.kind) for f in report.findings}


def test_compliant_plan_passes():
    report = check_plan(load("plan_compliant.json"), Config())
    assert report.passed
    assert report.findings == []
    # Two taggable resources; role assignment, data source and delete are not checked.
    assert report.checked == [
        "module.service.azurerm_log_analytics_workspace.this",
        "module.service.azurerm_container_app.this",
    ]


def test_tag_names_are_case_insensitive():
    report = check_plan(load("plan_compliant.json"), Config(required_tags=("OWNER", "Service")))
    assert report.passed


def test_violations_are_reported():
    cfg = Config(allowed_values={"environment": ("staging", "production")})
    report = check_plan(load("plan_violations.json"), cfg)
    assert not report.passed
    found = kinds(report)
    env = "module.service.azurerm_container_app_environment.this"
    assert (env, "cost-center", "missing") in found
    assert (env, "data-classification", "missing") in found  # empty string counts as missing
    assert (env, "environment", "invalid") in found
    for tag in Config().required_tags:
        assert ("azurerm_key_vault.shadow", tag, "missing") in found
    # delete-then-create (replace) is still checked because it includes "create"
    assert ("module.service.azurerm_container_app.this", "data-classification", "unknown") in found
    # no-op resources are not checked by default
    assert not any(a == "azurerm_public_ip.unchanged" for a, _, _ in found)


def test_unknown_values_are_warnings_by_default():
    report = check_plan(load("plan_violations.json"), Config())
    warned = {(f.address, f.tag) for f in report.warnings}
    assert ("azurerm_storage_account.computed", "owner") in warned
    assert all(f.kind != "unknown" for f in report.errors)


def test_fail_on_unknown_turns_warnings_into_errors():
    report = check_plan(load("plan_violations.json"), Config(fail_on_unknown=True))
    assert report.warnings == []
    assert any(f.kind == "unknown" for f in report.errors)


def test_ignore_rules_skip_resources():
    cfg = Config(
        ignore_addresses=("module.legacy.*",),
        ignore_resource_types=("azurerm_key_vault",),
    )
    report = check_plan(load("plan_violations.json"), cfg)
    addresses = {f.address for f in report.findings}
    assert "module.legacy.azurerm_resource_group.this" not in addresses
    assert "azurerm_key_vault.shadow" not in addresses
    assert set(report.skipped) == {
        "module.legacy.azurerm_resource_group.this",
        "azurerm_key_vault.shadow",
    }


def test_no_op_can_be_opted_in():
    report = check_plan(load("plan_violations.json"), Config(actions=("no-op",)))
    assert {f.address for f in report.findings} == {"azurerm_public_ip.unchanged"}


def test_allowed_values_apply_to_optional_tags_when_present():
    plan = {
        "format_version": "1.2",
        "resource_changes": [
            {
                "address": "azurerm_resource_group.rg",
                "mode": "managed",
                "type": "azurerm_resource_group",
                "change": {
                    "actions": ["create"],
                    "after": {"tags": {"owner": "me", "criticality": "extreme"}},
                    "after_unknown": {},
                },
            }
        ],
    }
    cfg = Config(required_tags=("owner",), allowed_values={"criticality": ("low", "high")})
    report = check_plan(plan, cfg)
    assert kinds(report) == {("azurerm_resource_group.rg", "criticality", "invalid")}


def test_empty_plan_passes():
    report = check_plan({"format_version": "1.2", "resource_changes": []}, Config())
    assert report.passed and report.checked == []


def test_rejects_non_plan_json():
    with pytest.raises(PlanError):
        check_plan({"hello": "world"}, Config())


def test_parse_list_handles_commas_newlines_and_comments():
    assert parse_list("a, b\n c\n# note\n\n") == ("a", "b", "c")
    assert parse_list("") == ()


def test_parse_allowed_values():
    parsed = parse_allowed_values("environment=staging|production\n# c\nTier = gold | silver")
    assert parsed == {"environment": ("staging", "production"), "tier": ("gold", "silver")}


@pytest.mark.parametrize("bad", ["environment", "=a|b", "env="])
def test_parse_allowed_values_rejects_bad_lines(bad):
    with pytest.raises(ValueError):
        parse_allowed_values(bad)
