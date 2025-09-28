#!/usr/bin/env bash
set -euo pipefail

# Rate limiting integration test against the gateway (NGINX at :3000)
# Verifies that bursts to /todos and /login yield some 429 responses
# while allowing some successful requests as well.

say() { printf "%s\n" "$*" >&2; }

wait_for_url() {
  local url="$1"; shift || true
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

# 1) Wait for frontend (acts as gateway)
say "Esperando frontend (gateway) en :3000..."
wait_for_url "http://localhost:3000/" 60 1 || { say "frontend no disponible"; exit 1; }

# 2) Acquire JWT via gateway /login (proxy to auth-api; limited at 1 r/s burst 5)
say "Obteniendo token vía gateway /login..."
LOGIN_RESP=$(curl -s -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}')
TOKEN=$(printf "%s" "$LOGIN_RESP" | sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [[ -z "${TOKEN:-}" ]]; then
  say "ERROR: no se pudo extraer accessToken del login"
  say "Respuesta: $LOGIN_RESP"
  exit 1
fi
say "Token adquirido (primeros 10): ${TOKEN:0:10}..."

# Helper to run a concurrent burst of curls and collect HTTP codes
burst_codes() {
  local n="$1"; shift
  local cmd=("$@")
  local tmp
  tmp=$(mktemp)
  for i in $(seq 1 "$n"); do
    ("${cmd[@]}" -s -o /dev/null -w "%{http_code}\n") >>"$tmp" &
  done
  wait
  cat "$tmp"
  rm -f "$tmp"
}

count_code() {
  local code="$1"; shift
  awk -v c="$code" 'BEGIN{n=0} $0==c{n++} END{print n+0}'
}

# 3) Burst to /todos through gateway with Authorization (expect some 429 and some 200)
say "Lanzando ráfaga a /todos vía gateway (30 req concurrentes)..."
mapfile -t TODOS_CODES < <( burst_codes 30 curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/todos )
TODOS_200=$(printf "%s\n" "${TODOS_CODES[@]}" | count_code 200)
TODOS_429=$(printf "%s\n" "${TODOS_CODES[@]}" | count_code 429)
say "/todos -> 200=$TODOS_200, 429=$TODOS_429"

if [[ "$TODOS_429" -lt 1 ]]; then
  say "ERROR: se esperaban algunos 429 en /todos y no se observaron"
  printf "%s\n" "${TODOS_CODES[@]}" >&2
  exit 1
fi
if [[ "$TODOS_200" -lt 1 ]]; then
  say "ERROR: todas las respuestas de /todos fueron limitadas; se esperaba al menos un 200"
  printf "%s\n" "${TODOS_CODES[@]}" >&2
  exit 1
fi

# 4) Burst to /login through gateway (12 concurrent logins) expecting multiple 429
say "Lanzando ráfaga a /login vía gateway (12 req concurrentes)..."
mapfile -t LOGIN_CODES < <( burst_codes 12 curl -H "Content-Type: application/json" -X POST \
  -d '{"username":"admin","password":"admin"}' http://localhost:3000/login )
LOGIN_200=$(printf "%s\n" "${LOGIN_CODES[@]}" | count_code 200)
LOGIN_429=$(printf "%s\n" "${LOGIN_CODES[@]}" | count_code 429)
say "/login -> 200=$LOGIN_200, 429=$LOGIN_429"

if [[ "$LOGIN_429" -lt 1 ]]; then
  say "ERROR: se esperaban algunos 429 en /login y no se observaron"
  printf "%s\n" "${LOGIN_CODES[@]}" >&2
  exit 1
fi

# 5) Summary
printf '{"todos":{"ok":%s,"limited":%s},"login":{"ok":%s,"limited":%s}}\n' \
  "$TODOS_200" "$TODOS_429" "$LOGIN_200" "$LOGIN_429"

say "Rate limiting test OK"
exit 0


