#!/usr/bin/env bash
# Service-specific smoke checks, run by the pipeline against each freshly
# deployed environment after the generic /version and health checks pass.
# BASE_URL is provided by the caller.
set -euo pipefail

price=$(curl -fsS --max-time 10 -X POST "$BASE_URL/api/v1/quotes" \
  -H 'Content-Type: application/json' \
  -d '{"weight_kg": 2, "distance_km": 100}' | jq -r .price_eur)

if [ "$price" != "7.8" ]; then
  echo "::error title=Smoke test::expected quote 7.8 EUR, got $price"
  exit 1
fi
echo "Quote endpoint OK ($price EUR)"
