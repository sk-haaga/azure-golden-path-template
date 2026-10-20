# Security model

## No stored secrets

| Where a secret would normally be | What this template does instead |
|---|---|
| Azure service principal secret in GitHub | GitHub OIDC → user-assigned managed identity with a federated credential |
| Terraform state storage key | `use_azuread_auth`; shared key access is disabled on the account |
| Registry admin password | Container App pulls with its own managed identity (AcrPull) |
| Azure OpenAI API key (remediation agent) | Short-lived Entra ID token obtained through OIDC at run time |

Everything stored in GitHub is a GitHub Actions *variable*: tenant ID, subscription ID, client IDs, resource
names. None of them grants access on its own; trust is defined on the Azure side, per identity, per subject.

## Least privilege per stage

Each OIDC identity trusts exactly one token subject:

- `ref:refs/heads/main` → **build**: can push images. Cannot touch any resource group.
- `pull_request` → **plan**: read-only on resource groups and state; plans run with `-lock=false`.
  Pull requests from forks get no OIDC token at all, so the plan job skips them.
- `environment:staging` / `environment:production` → **deploy-&lt;env&gt;**: Contributor on its own resource
  group only. A staging run cannot change production, and neither can grant roles.
- `environment:remediation` → **remediation**: only the Cognitive Services OpenAI User role.

Role assignments are created once by bootstrap, by a person. The pipeline can never widen its own access.

Environments are restricted to the `main` branch, and `production` has a required reviewer, so a deploy to
production needs both a merged commit and an approval.

## Scan gates

| Gate | When | Blocks on |
|---|---|---|
| Trivy filesystem (vulnerabilities, secrets, misconfigurations in Terraform and Dockerfiles) | PR and deploy | HIGH or CRITICAL with a fix available |
| Trivy image | PR and deploy (before push) | HIGH or CRITICAL with a fix available |
| require-tags | PR plan and every deploy plan | any missing or invalid required tag |
| Unit tests + ruff | PR and deploy | any failure |
| Smoke test | after each apply | new revision not live within 5 minutes, or a failed check |

Full Trivy results (all severities) are uploaded to GitHub code scanning. Accepted findings go in
`.trivyignore.yaml`, each scoped to a file path and with a written justification.

## Supply chain

- Third-party actions are pinned to full commit SHAs, with the version in a comment; Dependabot keeps them current.
- The image is built and scanned once and deployed **by digest**, so production runs the exact bytes that
  were scanned and tested in staging.
- Images run as a non-root user (UID 10001) on a slim base with OS packages upgraded at build time.
- `persist-credentials: false` on checkout everywhere except the remediation job, which must push a branch.

## Human in the loop

The remediation agent can open pull requests and issues, never merge. `main` requires a review and passing
checks, and CODEOWNERS routes changes to `.github/`, `actions/` and `infra/` to the platform owner.

Note: pull requests opened with the workflow's `GITHUB_TOKEN` do not trigger other workflows. The agent runs
the tests itself before opening a PR; to also get the PR checks, have the agent use a GitHub App token, or run
**Pull request checks** manually on its branch.
