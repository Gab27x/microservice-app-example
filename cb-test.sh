#!/usr/bin/env bash
set -euo pipefail

# ===================== Config (puedes override por ENV) ======================
AUTH_HOST="${AUTH_HOST:-localhost}"
TODOS_HOST="${TODOS_HOST:-localhost}"

# Puertos a probar (en orden). Cambia si usas otros.
AUTH_PORTS="${AUTH_PORTS:-8000 8081 8080}"
TODOS_PORTS="${TODOS_PORTS:-8082 3000 8080}"

# Rutas candidatas del endpoint de breaker
CB_PATHS=("/health/circuit-breaker" "/status/circuit-breaker" "/debug/breaker")

# Dependencias (nombres de contenedor en docker compose)
AUTH_DEP_CONTAINER="${AUTH_DEP_CONTAINER:-users-api}"
TODOS_DEP_CONTAINER="${TODOS_DEP_CONTAINER:-redis-todo}"

# Umbrales/tiempos
REQUESTS_TO_TRIP="${REQUESTS_TO_TRIP:-8}"   # envía más que tu umbral (p.ej. 5)
RESET_TIMEOUT_SEC="${RESET_TIMEOUT_SEC:-15}" # igual a tu open/reset timeout

# Endpoint de login (ajústalo si tu ruta real es otra)
LOGIN_PATH="${LOGIN_PATH:-/login}"
LOGIN_BODY='{"username":"admin","password":"admin"}'
# ============================================================================

say() { printf "%s\n" "$*" >&2; }

# Extrae "state" del JSON: usa jq si está disponible, si no usa grep (menos fiable)
extract_state() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.state // .circuit?.state // .circuit_breaker?.state // empty' 2>/dev/null || true
  else
    # lee de STDIN y busca la primera ocurrencia de "state":"..."
    grep -o '"state"\s*:\s*"[^"]*"' 2>/dev/null | head -1 | sed 's/.*"state"\s*:\s*"\([^"]*\)".*/\1/' || true
  fi
}

# Intenta encontrar un endpoint vivo devolviendo JSON con "state"
discover_cb_url() {
  local HOST="$1"; shift
  local PORTS_STR="$1"; shift || true
  local -a PORTS
  # split ports string into array
  read -r -a PORTS <<< "$PORTS_STR"
  local url out state
  for p in "${PORTS[@]}"; do
    for path in "${CB_PATHS[@]}"; do
      url="http://${HOST}:${p}${path}"
      say "Probando $url ..."
      out="$(curl -fs --max-time 2 "$url" 2>/dev/null || true)"
      if [ -n "$out" ]; then
        state="$(printf "%s" "$out" | extract_state)"
        if [ -n "$state" ]; then
          say "-> encontrado estado '$state' en $url"
          echo "$url"
          return 0
        else
          say "-> respuesta en $url pero no contiene 'state'"
        fi
      fi
    done
  done
  echo ""
}

# Enviar N logins para forzar el breaker
flood_logins() {
  local base="$1"; shift
  local n="${1:-8}"
  local url="${base}${LOGIN_PATH}"
  for i in $(seq 1 "$n"); do
    curl -s -X POST "$url" -H 'Content-Type: application/json' -d "$LOGIN_BODY" >/dev/null || true
    printf "."
  done
  echo
}

# Lee y muestra estado+JSON crudo
show_state() {
  local url="$1"
  local body; body="$(curl -fs "$url" 2>/dev/null || true)"
  local state; state="$(printf "%s" "$body" | extract_state)"
  echo "state: ${state:-unknown}"
  echo "$body"
}

# -------- Descubrimiento de endpoints --------
AUTH_CB_URL="${AUTH_CB_URL:-}"
TODOS_CB_URL="${TODOS_CB_URL:-}"

if [ -z "$AUTH_CB_URL" ]; then
  say "Buscando endpoint de breaker en auth-api..."
  AUTH_CB_URL="$(discover_cb_url "$AUTH_HOST" "$AUTH_PORTS")"
fi
if [ -z "$TODOS_CB_URL" ]; then
  say "Buscando endpoint de breaker en todos-api..."
  TODOS_CB_URL="$(discover_cb_url "$TODOS_HOST" "$TODOS_PORTS")"
fi

if [ -z "$AUTH_CB_URL" ]; then
  say "ERROR: no encontré endpoint de breaker en auth-api."
  say "Soluciones:"
  say "  1) Expón uno de estos paths: ${CB_PATHS[*]}"
  say "  2) O ejecuta con AUTH_CB_URL=http://host:puerto/<path>"
  exit 2
fi

say "AUTH_CB_URL = $AUTH_CB_URL"
[ -n "$TODOS_CB_URL" ] && say "TODOS_CB_URL = $TODOS_CB_URL" || say "TODOS_CB_URL no detectado (opcional)."

# ===== Escenario A: estado inicial (esperado CLOSED) =====
echo "== Escenario A: auth-api inicial =="
show_state "$AUTH_CB_URL"

# Base de auth (para logins)
AUTH_BASE="$(printf "%s" "$AUTH_CB_URL" | sed -E 's#(http://[^/]+).*#\1#')"

# ===== Escenario B: abrir breaker (apagar dependencia) =====
echo "== Escenario B: abrir breaker en auth-api =="
docker stop "$AUTH_DEP_CONTAINER" >/dev/null 2>&1 || true
flood_logins "$AUTH_BASE" "$REQUESTS_TO_TRIP"
show_state "$AUTH_CB_URL"

# ===== Escenario C: recuperación =====
echo "== Escenario C: recuperación auth-api =="
docker start "$AUTH_DEP_CONTAINER" >/dev/null 2>&1 || true
echo "Esperando ${RESET_TIMEOUT_SEC}s (open/reset timeout)..."
sleep "$RESET_TIMEOUT_SEC"
# dispara 1-2 req para cerrar half-open
flood_logins "$AUTH_BASE" 2
show_state "$AUTH_CB_URL"

# ===== Escenario D (opcional): todos-api/Redis =====
if [ -n "$TODOS_CB_URL" ]; then
  echo "== Escenario D (opcional): todos-api =="
  show_state "$TODOS_CB_URL"
  docker stop "$TODOS_DEP_CONTAINER" >/dev/null 2>&1 || true
  # Ajusta si tu endpoint real para crear TODOs es otro:
  for i in {1..8}; do curl -s -X POST "http://${TODOS_HOST}:8082/todos" -H 'Content-Type: application/json' -d '{"title":"x"}' >/dev/null || true; done
  show_state "$TODOS_CB_URL"
  docker start "$TODOS_DEP_CONTAINER" >/dev/null 2>&1 || true
  echo "Esperando ${RESET_TIMEOUT_SEC}s..."
  sleep "$RESET_TIMEOUT_SEC"
  for i in {1..2}; do curl -s -X POST "http://${TODOS_HOST}:8082/todos" -H 'Content-Type: application/json' -d '{"title":"y"}' >/dev/null || true; done
  show_state "$TODOS_CB_URL"
fi

echo "== Listo =="
