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
# Número de requests que enviará el script durante el "flood" para provocar fallos
REQUESTS_TO_TRIP="${REQUESTS_TO_TRIP:-20}"   # aumenta para asegurar tripping
# Tiempo que espera antes de intentar recuperación (coincide con el timeout del breaker)
RESET_TIMEOUT_SEC="${RESET_TIMEOUT_SEC:-15}" # segundos

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
  # enviar peticiones en paralelo para forzar errores rápidamente
  for i in $(seq 1 "$n"); do
    (curl -s -X POST "$url" -H 'Content-Type: application/json' -d "$LOGIN_BODY" >/dev/null 2>&1 || true) &
  done
  wait
  echo
}

# Espera hasta que el endpoint del breaker alcance el estado deseado.
# Uso: wait_for_state <url> <state> [timeout_seconds]
wait_for_state() {
  local url="$1"; local target="$2"; local timeout="${3:-15}"
  local waited=0
  while [ $waited -lt $timeout ]; do
    local body; body="$(curl -fs "$url" 2>/dev/null || true)"
    local state; state="$(printf "%s" "$body" | extract_state)"
    if [ "$state" = "$target" ]; then
      return 0
    fi
    sleep 1
    waited=$((waited+1))
  done
  return 1
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
say "Parando dependencia $AUTH_DEP_CONTAINER para forzar errores..."
docker stop "$AUTH_DEP_CONTAINER" >/dev/null 2>&1 || true
sleep 1
say "Inundando $REQUESTS_TO_TRIP requests de login para provocar fallos..."
flood_logins "$AUTH_BASE" "$REQUESTS_TO_TRIP"
say "Comprobando si el breaker pasó a 'open' (esperando hasta 15s)..."
if wait_for_state "$AUTH_CB_URL" "open" 15; then
  say "-> El breaker está OPEN"
else
  say "-> No detecté OPEN en el timeout; mostrando estado actual"
fi
show_state "$AUTH_CB_URL"

# ===== Escenario C: recuperación =====
echo "== Escenario C: recuperación auth-api =="
say "Arrancando dependencia $AUTH_DEP_CONTAINER..."
docker start "$AUTH_DEP_CONTAINER" >/dev/null 2>&1 || true
say "Esperando ${RESET_TIMEOUT_SEC}s (open/reset timeout) para entrar en half-open..."
sleep "$RESET_TIMEOUT_SEC"
say "Buscando estado 'half-open' durante ${RESET_TIMEOUT_SEC}s..."
if wait_for_state "$AUTH_CB_URL" "half-open" "$RESET_TIMEOUT_SEC"; then
  say "-> half-open detectado: esperando a que users-api esté listo y envío 3 requests de prueba"
  # esperar hasta que users-api responda en el puerto 8083
  wait_for_service() {
    local host=${1:-localhost}
    local port=${2:-8083}
    local timeout=${3:-30}
    local waited=0
    while [ $waited -lt $timeout ]; do
      if curl -fs "http://${host}:${port}/" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
      waited=$((waited+1))
    done
    return 1
  }

  if wait_for_service "localhost" 8083 30; then
    say "users-api listo — enviando 3 peticiones de prueba hacia auth-api/login"
    flood_logins "$AUTH_BASE" 3
  else
    say "Warning: users-api no respondió en 30s; las peticiones de prueba pueden fallar"
    flood_logins "$AUTH_BASE" 3
  fi
  say "Esperando a que el breaker cierre (closed) durante ${RESET_TIMEOUT_SEC}s..."
  if wait_for_state "$AUTH_CB_URL" "closed" "$RESET_TIMEOUT_SEC"; then
    say "-> recovery exitoso: breaker CLOSED"
  else
    say "-> No se detectó CLOSED después de pruebas; mostrar estado actual"
  fi
else
  say "-> No se detectó half-open (quizá el breaker cerró directamente o no hubo timeout)."
fi
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
