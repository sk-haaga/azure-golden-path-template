# Measuring "repo to running"

Two numbers are worth reporting, and both come from GitHub's own records rather than a stopwatch.

| Metric | From → to | Where |
|---|---|---|
| **Repo to running** | repository created → first successful staging deployment | `python3 scripts/lead_time.py <owner>/<repo>` |
| **Commit to running** | Deploy workflow starts → staging smoke test passes | each Deploy run's summary, and the same script |

"Repo to running" includes the manual parts (editing `golden-path.yaml`, bootstrap, `configure-github.sh`),
which is the honest measure of how fast a new team can ship.

## A clean measurement

1. On GitHub, **Use this template** → create `sk-haaga/demo-service`. The clock starts here.
2. Clone it, set `service.name: demo-service` in `golden-path.yaml`, commit.
3. `infra/bootstrap`: copy the tfvars example, set the repo name, `terraform apply`.
4. `scripts/configure-github.sh sk-haaga/demo-service`
5. `git push`, wait for staging to go green.
6. `python3 scripts/lead_time.py sk-haaga/demo-service`

Example output:

```
Repository:           sk-haaga/demo-service
Created:              2026-10-20 09:02 UTC
First staging live:   2026-10-20 09:21 UTC
Repo to running:      19m 04s
Commit to running:    6m 41s (latest, 3f9c2ab)
```

(Illustrative numbers. Use your own measured result.)

Run it two or three times and report the median. Clean up a test service with `terraform destroy` in
`infra/service` (per environment) and then in `infra/bootstrap`.
