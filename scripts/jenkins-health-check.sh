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
        # Intentar con curl y capturar más información
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
        
        if [[ "$response_code" =~ ^[23][0-9][0-9]$ ]]; then
            say "$SERVICE_NAME está disponible ✅ (HTTP $response_code)"
            return 0
        elif [[ "$response_code" != "000" ]]; then
            say "Intento $i/$tries - $SERVICE_NAME respondió con HTTP $response_code, reintentando..."
        else
            say "Intento $i/$tries - $SERVICE_NAME no responde (timeout/conexión rechazada), reintentando..."
        fi
        
        sleep "$sleep_s"
    done
    
    # Último intento con información detallada del error
    say "Realizando diagnóstico final..."
    local final_error
    final_error=$(curl -s --max-time 10 "$url" 2>&1 || echo "Sin respuesta")
    say "Error final: $final_error"
    
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