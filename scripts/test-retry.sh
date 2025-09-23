#!/usr/bin/env bash
set -euo pipefail

# Deterministic retry verification for auth-api using WireMock.
# Works locally and in GitHub Actions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

say() { printf "%s\n" "$*" >&2; }

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    say "Installing jq (required for metrics parsing)..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y >/dev/null 2>&1 || true
      sudo apt-get install -y jq >/dev/null 2>&1 || true
    fi
  fi
  command -v jq >/dev/null 2>&1 || { say "WARNING: jq not found; metrics will be limited"; return 1; }
}

need_jq || true

# Wait for a URL to be ready (HTTP 2xx/3xx)
wait_for_url() {
  local url="$1"; shift
  local tries="${1:-60}"; shift || true
  local sleep_s="${1:-1}"; shift || true
  for i in $(seq 1 "$tries"); do
    if curl -fs "$url" >/dev/null 2>&1; then
      return 0
    fi
    printf "." >&2
    sleep "$sleep_s"
  done
  printf "\n" >&2
  return 1
}

# POST JSON with retries to handle transient readiness
post_json_retry() {
  local url="$1"; shift
  local data="$1"; shift
  curl --retry 6 --retry-delay 1 --retry-connrefused -fsS -X POST "$url" \
    -H "Content-Type: application/json" -d "$data" >/dev/null
}

# 1) Bring up stack with WireMock override (auth-api points to wiremock)
say "Starting stack with WireMock override..."
docker compose -f "$ROOT_DIR/docker-compose.yml" -f "$ROOT_DIR/docker-compose.retry.yml" up -d --build wiremock zipkin auth-api

# 1.1) Wait for WireMock to be ready before admin calls
say "Waiting for WireMock to be ready..."
wait_for_url "http://localhost:8089/__admin/mappings" 40 0.5 || {
  say "WireMock didn't become ready in time"; exit 1; }

# 2) Wait for auth-api to be ready
AUTH_URL="http://localhost:8000/version"
for i in {1..30}; do
  if curl -fs "$AUTH_URL" >/dev/null 2>&1; then
    break
  fi
  say "Waiting for auth-api... ($i)"
  sleep 2
done

# 3) Program WireMock: first GET /users/* returns 500, second returns 200
# Reset WireMock (clean mappings and requests) to avoid leftovers from previous runs
say "Resetting WireMock mappings and requests..."
curl -fsS -X POST http://localhost:8089/__admin/reset >/dev/null || true
curl -fsS -X POST http://localhost:8089/__admin/requests/reset >/dev/null || true

say "Configuring WireMock stubs..."
post_json_retry http://localhost:8089/__admin/mappings '{
  "scenarioName": "UsersApiFlaky",
  "requiredScenarioState": "Started",
  "newScenarioState": "FailOnce",
  "request": { "method": "GET", "urlPathPattern": "/users/.*" },
  "response": { "status": 500, "jsonBody": { "error": "temporary" }, "headers": { "Content-Type": "application/json" } }
}'
post_json_retry http://localhost:8089/__admin/mappings '{
  "scenarioName": "UsersApiFlaky",
  "requiredScenarioState": "FailOnce",
  "newScenarioState": "Succeeded",
  "request": { "method": "GET", "urlPathPattern": "/users/.*" },
  "response": { "status": 200, "jsonBody": { "username":"admin","firstname":"Admin","lastname":"User","role":"ADMIN" }, "headers": { "Content-Type": "application/json" } }
}'

# 4) Wait until both stubs are loaded and scenario is in Started state (only if jq available)
if command -v jq >/dev/null 2>&1; then
  say "Waiting for WireMock scenario and stubs to be ready..."
  for i in {1..40}; do
    SCEN_STATE=$(curl -fs http://localhost:8089/__admin/scenarios | (jq -r '.scenarios[] | select(.name=="UsersApiFlaky") | .state' 2>/dev/null || true))
    MAPS=$(curl -fs http://localhost:8089/__admin/mappings | (jq -r '[.mappings[] | select(.scenarioName=="UsersApiFlaky")] | length' 2>/dev/null || true))
    if [[ "${SCEN_STATE:-}" == "Started" && "${MAPS:-0}" -ge 2 ]]; then
      break
    fi
    printf "." >&2
    sleep 0.25
  done
  printf "\n" >&2
  # Small extra settle time
  sleep 0.6
else
  say "jq not available; skipping scenario readiness wait (sleeping 1s)"
  sleep 1
fi

# 5) Capture breaker totals before
CB_URL="http://localhost:8000/status/circuit-breaker"
BEFORE_REQS=""
if command -v jq >/dev/null 2>&1; then
  BEFORE_REQS=$(curl -fs "$CB_URL" | jq -r '.totals.Requests // .Requests // 0' || echo "0")
fi

# 6) Call /login and expect 200 despite first 500, measuring elapsed
say "Calling /login expecting success after retry..."
start_ns=$(date +%s%N 2>/dev/null || echo "0")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}')
end_ns=$(date +%s%N 2>/dev/null || echo "0")

if [[ "$HTTP_CODE" != "200" ]]; then
  say "ERROR: expected 200 from /login, got $HTTP_CODE"
  curl -s http://localhost:8089/__admin/requests | sed -e 's/{/\n{/g' | tail -n 30 >&2 || true
  exit 1
fi

# 7) Collect metrics: wiremock requests and statuses, breaker delta, elapsed ms
WIRE_REQ_COUNT=""
STATUSES_JSON="[]"
AFTER_REQS=""

if command -v jq >/dev/null 2>&1; then
  WIRE_REQ_COUNT=$(curl -fs http://localhost:8089/__admin/requests | jq '.requests | length')
  STATUSES_JSON=$(curl -fs http://localhost:8089/__admin/requests | jq '[.requests[] | select(.request.url|test("/users/")) | {status:.response.status, t:(.loggedDate // 0)}] | sort_by(.t) | .[-2:] | map(.status)')
  AFTER_REQS=$(curl -fs "$CB_URL" | jq -r '.totals.Requests // .Requests // 0')
fi

ELAPSED_MS=""
if [[ "$start_ns" != "0" && "$end_ns" != "0" ]]; then
  # convert ns to ms (bash integer arithmetic)
  ELAPSED_MS=$(( (end_ns - start_ns)/1000000 ))
fi

# 8) Assertions with metrics when jq available
if command -v jq >/dev/null 2>&1; then
  # Expect the last two users-api responses to be a set {500,200} regardless of order
  SORTED_STATUSES=$(printf "%s" "$STATUSES_JSON" | jq 'sort')
  if [[ "$(echo "$SORTED_STATUSES" | tr -d '[:space:]')" != "[200,500]" ]]; then
    say "ERROR: expected users-api statuses {500,200}, got: $STATUSES_JSON"
    exit 1
  fi
  # Expect breaker delta requests to be 2
  DELTA=$(( AFTER_REQS - BEFORE_REQS ))
  if [[ "$DELTA" -lt 2 ]]; then
    say "ERROR: expected breaker to observe at least 2 outbound attempts, got $DELTA"
    exit 1
  fi
fi

# 9) Report metrics summary
say "Retry test passed. Summary:"
printf '{"httpCode":%s,"wiremockRequestCount":%s,"usersApiLastStatuses":%s,"breakerDeltaRequests":%s,"elapsedMs":%s}\n' \
  "${HTTP_CODE:-0}" \
  "${WIRE_REQ_COUNT:-null}" \
  "${STATUSES_JSON:-[]}" \
  "${DELTA:-null}" \
  "${ELAPSED_MS:-null}"

exit 0


