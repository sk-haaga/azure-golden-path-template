#!/usr/bin/env python3
"""Measure how long the golden path takes, from GitHub's own records.

    python scripts/lead_time.py [owner/repo]

Reports two numbers:

* repo to running: repository creation -> first successful staging deployment.
  This is the "a new service goes from repo to running in X" figure, and it
  includes the one-time bootstrap a team does by hand.
* commit to running: for the latest successful staging deployment, the start of
  the Deploy workflow run -> staging deployment marked successful.

Needs the GitHub CLI (`gh`) logged in with read access to the repository.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime


def gh(*args: str) -> object:
    out = subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else None


def ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def fmt(seconds: float) -> str:
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}h {m:02d}m {s:02d}s" if h else f"{m}m {s:02d}s"


def successful_deployments(repo: str, environment: str) -> list[tuple[dict, datetime]]:
    deployments = gh("api", f"repos/{repo}/deployments?environment={environment}&per_page=100")
    result = []
    for d in deployments or []:
        statuses = gh("api", f"repos/{repo}/deployments/{d['id']}/statuses?per_page=100") or []
        ok = [ts(s["created_at"]) for s in statuses if s["state"] == "success"]
        if ok:
            result.append((d, min(ok)))
    return sorted(result, key=lambda item: item[1])


def main() -> int:
    repo = (
        sys.argv[1]
        if len(sys.argv) > 1
        else gh("repo", "view", "--json", "nameWithOwner")["nameWithOwner"]
    )
    created = ts(gh("api", f"repos/{repo}")["created_at"])
    staging = successful_deployments(repo, "staging")
    if not staging:
        print(f"{repo}: no successful staging deployment yet.")
        return 1

    first_deploy, first_live = staging[0]
    print(f"Repository:           {repo}")
    print(f"Created:              {created:%Y-%m-%d %H:%M} UTC")
    print(f"First staging live:   {first_live:%Y-%m-%d %H:%M} UTC")
    print(f"Repo to running:      {fmt((first_live - created).total_seconds())}")

    latest_deploy, latest_live = staging[-1]
    runs = (
        gh(
            "run",
            "list",
            "--repo",
            repo,
            "--workflow",
            "deploy.yml",
            "--commit",
            latest_deploy["sha"],
            "--json",
            "startedAt,databaseId",
            "--limit",
            "5",
        )
        or []
    )
    if runs:
        started = min(ts(r["startedAt"]) for r in runs)
        print(
            f"Commit to running:    {fmt((latest_live - started).total_seconds())} "
            f"(latest, {latest_deploy['sha'][:7]})"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
