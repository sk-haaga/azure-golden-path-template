import json
from pathlib import Path

from require_tags.__main__ import main

FIXTURES = Path(__file__).parent / "fixtures"


def gh_files(tmp_path, monkeypatch):
    out, summary = tmp_path / "out", tmp_path / "summary.md"
    out.touch()
    summary.touch()
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    return out, summary


def test_passing_plan_exits_zero_and_writes_outputs(tmp_path, monkeypatch, capsys):
    out, summary = gh_files(tmp_path, monkeypatch)
    code = main(["--plan-json", str(FIXTURES / "plan_compliant.json")])
    assert code == 0
    outputs = out.read_text()
    assert "passed=true" in outputs and "violations=0" in outputs and "checked=2" in outputs
    assert "✅ Passed" in summary.read_text()
    assert "::error" not in capsys.readouterr().out


def test_violations_exit_one_with_annotations(tmp_path, monkeypatch, capsys):
    out, summary = gh_files(tmp_path, monkeypatch)
    report_path = tmp_path / "report.json"
    code = main(
        [
            "--plan-json",
            str(FIXTURES / "plan_violations.json"),
            "--allowed-values",
            "environment=staging|production",
            "--ignore-addresses",
            "",
            "--report-path",
            str(report_path),
        ]
    )
    assert code == 1
    printed = capsys.readouterr().out
    assert "::error title=require-tags: missing tag 'owner'::azurerm_key_vault.shadow" in printed
    assert "::warning" in printed
    assert "passed=false" in out.read_text()
    assert "❌ Blocked" in summary.read_text()
    report = json.loads(report_path.read_text())
    assert report["passed"] is False and len(report["errors"]) > 0


def test_missing_file_is_a_usage_error(tmp_path, monkeypatch, capsys):
    gh_files(tmp_path, monkeypatch)
    assert main(["--plan-json", str(tmp_path / "nope.json")]) == 2
    assert "Plan file not found" in capsys.readouterr().out


def test_invalid_json_is_a_usage_error(tmp_path, monkeypatch):
    gh_files(tmp_path, monkeypatch)
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert main(["--plan-json", str(bad)]) == 2


def test_bad_allowed_values_is_a_usage_error(tmp_path, monkeypatch):
    gh_files(tmp_path, monkeypatch)
    code = main(["--plan-json", str(FIXTURES / "plan_compliant.json"), "--allowed-values", "oops"])
    assert code == 2
