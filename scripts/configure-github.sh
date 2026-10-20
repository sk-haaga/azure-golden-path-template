#!/usr/bin/env bash
# Wire a repository to the Azure resources created by infra/bootstrap.
#
#   scripts/configure-github.sh [owner/repo]
#
# Sets GitHub Actions *variables* (not secrets: OIDC needs none), creates the
# staging / production / remediation environments with a main-only deployment
# policy, puts a required reviewer on production, and protects main so that
# nothing (including the remediation agent) can merge without a review.
#
# Requires: gh (logged in, admin on the repo), terraform, jq.
# Note: on a personal account, environment reviewers and branch protection on
# *private* repositories need GitHub Pro. Without it those steps are skipped
# with a warning and everything else still works.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-1}"
echo "Configuring $REPO"

out=$(terraform -chdir=infra/bootstrap output -json)

echo "-> repository variables"
jq -r '.github_repository_variables.value | to_entries[] | "\(.key)\t\(.value)"' <<<"$out" |
  while IFS=$'\t' read -r key value; do
    gh variable set "$key" --repo "$REPO" --body "$value"
    echo "   $key"
  done

reviewer_id=$(gh api user -q .id)

warn() { echo "   WARNING: $*" >&2; }

create_env() {
  local env="$1" reviewers="$2"
  local body
  body=$(jq -n --argjson reviewers "$reviewers" '{
      wait_timer: 0,
      reviewers: $reviewers,
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}
    }')
  if ! gh api -X PUT "repos/$REPO/environments/$env" --input - <<<"$body" >/dev/null 2>&1; then
    warn "could not set reviewers on '$env' (plan limit?); creating it without them"
    gh api -X PUT "repos/$REPO/environments/$env" >/dev/null
  fi
  gh api -X POST "repos/$REPO/environments/$env/deployment-branch-policies" \
    -f name=main -f type=branch >/dev/null 2>&1 || true
}

echo "-> environments"
for env in $(jq -r '.github_environment_variables.value | keys[]' <<<"$out"); do
  if [ "$env" = "production" ]; then
    create_env "$env" "[{\"type\":\"User\",\"id\":$reviewer_id}]"
  else
    create_env "$env" "[]"
  fi
  jq -r --arg e "$env" '.github_environment_variables.value[$e] | to_entries[] | "\(.key)\t\(.value)"' <<<"$out" |
    while IFS=$'\t' read -r key value; do
      gh variable set "$key" --repo "$REPO" --env "$env" --body "$value"
    done
  echo "   $env"
done

echo "-> branch protection on main"
protection=$(jq -n --argjson n "$REQUIRED_APPROVALS" '{
  required_status_checks: {
    strict: true,
    contexts: [
      "App - lint and tests",
      "require-tags action - tests and self-check",
      "Security scan (Trivy)"
    ]
  },
  enforce_admins: false,
  required_pull_request_reviews: {
    required_approving_review_count: $n,
    dismiss_stale_reviews: true,
    require_code_owner_reviews: true
  },
  restrictions: null,
  allow_force_pushes: false,
  allow_deletions: false
}')
if gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<<"$protection" >/dev/null 2>&1; then
  echo "   main requires $REQUIRED_APPROVALS review(s) and passing checks"
else
  warn "branch protection not applied (plan limit, or main does not exist yet)"
fi

cat <<EOF

Done. Optional, for the Vulnerability Remediation Agent:
  gh variable set REMEDIATION_AGENT_IMAGE  --repo $REPO --body ghcr.io/<owner>/vulnerability-remediation-agent:latest
  gh variable set AZURE_OPENAI_ENDPOINT    --repo $REPO --body https://<account>.openai.azure.com
  gh variable set AZURE_OPENAI_DEPLOYMENT  --repo $REPO --body <deployment-name>
Then push to main, or run the Deploy workflow, to ship.
EOF
