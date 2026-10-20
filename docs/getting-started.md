# Getting started: ship a new service

This takes a service from an empty repository to running in Azure. Steps 1–4 happen once per service;
after that, every push to `main` deploys.

## What you need

- An Azure subscription, and an account that is **Owner** (or Contributor + Role Based Access Control
  Administrator) on it. Only bootstrap needs this; the pipeline itself never has it.
- Terraform ≥ 1.9, Azure CLI, GitHub CLI (`gh`), `jq`.
- A GitHub repository created from this template.

## 1. Describe the service

Edit `golden-path.yaml`:

```yaml
service:
  name: orders-api            # used in every Azure resource name
  owner: team-checkout
  cost_center: CC-2040
  data_classification: confidential
```

Every value under `service` becomes a tag on every Azure resource. The pipeline refuses to deploy if any
resource ends up without them.

Replace `app/` with your service. The template expects:

- a `Dockerfile` that serves HTTP on `runtime.port`
- liveness and readiness endpoints (`runtime.liveness_path`, `runtime.readiness_path`)
- `GET /version` returning JSON with `git_sha` (the pipeline uses it to confirm the new revision is live).
  The image receives `GIT_SHA` as an environment variable.
- `requirements-dev.txt` and tests runnable with `pytest`
- optionally `tests/smoke.sh` for service-specific checks after each deployment

## 2. Bootstrap Azure (once)

```bash
az login
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars    # set subscription_id, github_owner, github_repo
terraform init
terraform apply
```

This creates, in about five minutes:

- `rg-<service>-platform` with the container registry, the Terraform state account (Entra ID auth only,
  versioned, soft delete) and the GitHub OIDC identities
- `rg-<service>-staging` and `rg-<service>-production`, each with the managed identity its app uses to pull images

Keep the bootstrap `terraform.tfstate` safe. It is local by design because nothing exists yet to store it in.

## 3. Connect GitHub

```bash
cd ../..
scripts/configure-github.sh            # or: scripts/configure-github.sh sk-haaga/orders-api
```

This writes the IDs from bootstrap as GitHub Actions **variables**, creates the `staging`, `production`
(with you as required reviewer) and `remediation` environments, restricts them to `main`, and protects `main`.

> On a free personal account, required reviewers and branch protection only work on public repositories.
> The script warns and continues; deployments still work, just without the approval gate.

## 4. Ship

```bash
git commit -am "Describe orders-api" && git push
```

Watch **Actions → Deploy**. The run summary shows the image digest, the tag check result, the staging URL and
how long it took from push to running. Approve the production job when you are happy with staging.

## Day to day

- **Pull requests** run tests, Trivy, `terraform validate`, and a read-only plan for both environments.
  The plan and tag check are posted as a PR comment.
- **Merging to main** deploys to staging automatically and to production after approval.
- **Mondays**, the Vulnerability Remediation Agent opens PRs for safe dependency upgrades (if configured).

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Golden path not configured: Missing repository variables` | Run step 3. |
| `AADSTS70021: No matching federated identity record found` | Repository name in `terraform.tfvars` does not match the GitHub repo, or the job is not running from `main` / the expected environment. |
| Required tags check ❌ | A resource in the plan has no tags or a bad value. The job summary lists each resource and tag. |
| Smoke test timed out | The new revision did not start. Check the Container App's revision logs in Log Analytics; often the port in `golden-path.yaml` does not match the app. |
| `AuthorizationFailed` on apply | The resource is outside the environment's resource group. Deploy identities can only change their own group. |
