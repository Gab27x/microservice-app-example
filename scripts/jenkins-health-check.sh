#!/usr/bin/env bash
set -euo pipefail

# Script para verificar health checks básicos
# Uso: ./jenkins-health-check.sh <URL> <SERVICE_NAME> <TIMEOUT>

URL="$1"
SERVICE_NAME="$2"
TIMEOUT="${3:-60}"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

say "Verificando $SERVICE_NAME en $URL (timeout: ${TIMEOUT}s)"

# Wait for a URL to be ready (HTTP 2xx/3xx)
wait_for_url() {
    local url="$1"
    local tries="$2"
    local sleep_s="${3:-1}"
    
    for i in $(seq 1 "$tries"); do
        if curl -fs --max-time 5 "$url" >/dev/null 2>&1; then
            say "$SERVICE_NAME está disponible ✅"
            return 0
        fi
        say "Intento $i/$tries - $SERVICE_NAME no disponible aún..."
        sleep "$sleep_s"
    done
    
    say "$SERVICE_NAME no está disponible después de $tries intentos ❌"
    return 1
}

# Instalar curl si no está disponible
if ! command -v curl >/dev/null 2>&1; then
    say "Instalando curl..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y >/dev/null 2>&1 || true
        sudo apt-get install -y curl >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y curl >/dev/null 2>&1 || true
    fi
fi

# Ejecutar health check
wait_for_url "$URL" "$TIMEOUT" 2

say "$SERVICE_NAME health check completado"