# require-tags

A GitHub Action, written in Python and packaged with Docker, that **blocks a deployment when Azure
resources in a Terraform plan are missing required tags** or use a tag value that is not allowed.

Tags are how cost, ownership and data handling are tracked in Azure. Checking them in the plan,
before `apply`, means an untagged resource never gets created in the first place.

## Usage

```yaml
- run: |
    terraform plan -out=tfplan
    terraform show -json tfplan > tfplan.json

- uses: ./actions/require-tags          # or sk-haaga/azure-golden-path-template/actions/require-tags@v1
  with:
    plan-json: tfplan.json
    required-tags: owner,cost-center,environment,service,data-classification
    allowed-values: |
      environment=staging|production
      data-classification=public|internal|confidential
```

The step fails (exit code 1) when there are violations, so the following `terraform apply` never runs.

## Inputs

| Input | Default | Description |
|---|---|---|
| `plan-json` | (required) | Output of `terraform show -json <planfile>` |
| `required-tags` | `owner,cost-center,environment,service,data-classification` | Comma- or newline-separated |
| `allowed-values` | | Lines of `key=value1\|value2`. Also applies to optional tags when present |
| `ignore-resource-types` | | e.g. `azurerm_monitor_diagnostic_setting` |
| `ignore-addresses` | | Glob patterns, e.g. `module.legacy.*` |
| `actions` | `create,update` | Add `no-op` to also enforce on unchanged resources |
| `tag-attribute` | `tags` | Attribute holding tags in the provider schema |
| `fail-on-unknown` | `false` | Treat values only known after apply as violations |
| `report-path` | | Also write the JSON report to a file |

## Outputs

`passed`, `violations`, `warnings`, `checked`, `report` (JSON).

## How it decides

- Only `managed` resources whose planned actions include one of `actions` are checked.
  A replace (`delete` + `create`) counts as a create.
- A resource type without a `tags` attribute (role assignments, federated credentials…) never has
  `tags` in the plan, so it is skipped automatically. No allow-list to maintain.
- Tag names are compared case-insensitively, as Azure does. Empty values count as missing.
- If tags are computed and only known after apply, the action cannot verify them; it warns by default.

## Development

```bash
cd actions/require-tags
pip install pytest pytest-cov ruff
pytest --cov=require_tags      # 20 tests, ~100% coverage
PYTHONPATH=src python -m require_tags --plan-json tests/fixtures/plan_violations.json
docker build -t require-tags . && docker run --rm -v "$PWD:/w" -w /w require-tags --plan-json tests/fixtures/plan_compliant.json
```

It uses only the Python standard library, so the image is a plain `python:alpine` base plus the source.
