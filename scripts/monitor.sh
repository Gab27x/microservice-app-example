#!/usr/bin/env bash
set -euo pipefail

# Script de Monitor para Microservicios
# Monitorea servicios usando docker.sh y verificaciones HTTP

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DOCKER_SCRIPT="${SCRIPT_DIR}/docker.sh"

say() { printf "%s\n" "$*" >&2; }
success() { printf "${GREEN}✓ %s${NC}\n" "$*" >&2; }
error() { printf "${RED}✗ %s${NC}\n" "$*" >&2; }
warning() { printf "${YELLOW}⚠ %s${NC}\n" "$*" >&2; }
info() { printf "${BLUE}ℹ %s${NC}\n" "$*" >&2; }

# Configuración
SERVICES=(
    "redis-todo:6379:redis"
    "zipkin:9411:zipkin"
    "users-api:8083:docker"
    "auth-api:8000:http"
    "todos-api:8082:docker"
    "frontend:3000:http"
    "log-message-processor:running:docker"
)
MONITOR_INTERVAL=30
ALERT_THRESHOLD=3

# Función para verificar conectividad HTTP
check_http_service() {
    local name="$1"
    local host="$2"
    local port="$3"
    local path="${4:-/health}"
    local timeout="${5:-5}"
    
    if curl -fs --max-time "$timeout" "http://$host:$port$path" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Función para verificar conectividad TCP
check_tcp_service() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Función para verificar estado del contenedor Docker
check_docker_container() {
    local service_name="$1"
    
    if bash "$DOCKER_SCRIPT" ps | grep -q "$service_name.*Up"; then
        return 0
    else
        return 1
    fi
}

# Función para obtener métricas específicas de cada servicio
get_service_metrics() {
    local service="$1"
    local host="$2"
    local port="$3"

    case "$service" in
        "auth-api")
            # Verificar estado del circuit breaker (endpoint disponible sin auth)
            if check_http_service "$service" "$host" "$port" "/health/circuit-breaker" 2; then
                local cb_state
                cb_state=$(curl -s "http://$host:$port/health/circuit-breaker" 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
                echo "CB:$cb_state"
            else
                echo "CB:N/A"
            fi
            ;;
        "todos-api")
            # Como requiere auth, solo verificar si contenedor está corriendo
            if check_docker_container "$service"; then
                echo "Container:OK"
            else
                echo "Container:DOWN"
            fi
            ;;
        "users-api")
            # Como requiere auth, solo verificar si contenedor está corriendo
            if check_docker_container "$service"; then
                echo "Container:OK"
            else
                echo "Container:DOWN"
            fi
            ;;
        "redis-todo")
            # Verificar Redis
            if timeout 2 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
                echo "Redis:PONG"
            else
                echo "Redis:DOWN"
            fi
            ;;
        "zipkin")
            if check_http_service "$service" "$host" "$port" "/" 2; then
                echo "UI:OK"
            else
                echo "UI:FAIL"
            fi
            ;;
        "frontend")
            if check_http_service "$service" "$host" "$port" "/" 2; then
                echo "Vue:OK"
            else
                echo "Vue:FAIL"
            fi
            ;;
        "log-message-processor")
            if check_docker_container "$service"; then
                echo "Running"
            else
                echo "Stopped"
            fi
            ;;
    esac
}

# Función para mostrar estado de un servicio y devolver fallos
show_service_status() {
    local service="$1"
    local host="$2"
    local port="$3"
    local check_type="$4"
    local failures="${5:-0}"

    if [[ "$check_type" == "redis" ]]; then
        if check_tcp_service "$host" "$port"; then
            printf "${GREEN}✓ %-20s ${BLUE}%s:%s${NC}" "$service" "$host" "$port"
            failures=0
        else
            printf "${RED}✗ %-20s ${BLUE}%s:%s${NC}" "$service" "$host" "$port"
            ((failures++))
        fi
    elif [[ "$check_type" == "docker" ]]; then
        if check_docker_container "$service"; then
            printf "${GREEN}✓ %-20s ${BLUE}Container${NC}" "$service"
            failures=0
        else
            printf "${RED}✗ %-20s ${BLUE}Container${NC}" "$service"
            ((failures++))
        fi
    else
        # Usar endpoint específico para cada servicio
        local endpoint="/"
        if [[ "$service" == "auth-api" ]]; then
            endpoint="/health/circuit-breaker"
        fi

        if check_http_service "$service" "$host" "$port" "$endpoint" 3; then
            printf "${GREEN}✓ %-20s ${BLUE}%s:%s${NC}" "$service" "$host" "$port"
            failures=0
        else
            printf "${RED}✗ %-20s ${BLUE}%s:%s${NC}" "$service" "$host" "$port"
            ((failures++))
        fi
    fi

    # Mostrar métricas
    local metrics
    metrics=$(get_service_metrics "$service" "$host" "$port")
    if [ -n "$metrics" ]; then
        printf " ${YELLOW}[$metrics]${NC}"
    fi

    # Mostrar contador de fallos
    if [ "$failures" -gt 0 ]; then
        printf " ${RED}(${failures} fallos)${NC}"
    fi

    echo

    # Devolver el número de fallos como código de salida
    return $failures
}

# Función para mostrar estado de todos los servicios
show_all_status() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo
    info "Estado de Servicios - $timestamp"
    echo "======================================"
    
    declare -A service_failures
    
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port check_type <<< "$service_info"
        host="localhost"

        local current_failures="${service_failures[$service]:-0}"
        # La función devuelve el código de error (número de fallos)
        show_service_status "$service" "$host" "$port" "$check_type" "$current_failures"
        local new_failures=$?
        service_failures[$service]="$new_failures"

        if [ "$new_failures" -ge "$ALERT_THRESHOLD" ]; then
            warning "ALERTA: $service ha fallado $new_failures veces consecutivas"
        fi
    done
}

# Función para mostrar logs usando docker.sh
show_logs() {
    local service="$1"
    local follow="${2:-false}"
    
    if [ -n "$service" ]; then
        info "Mostrando logs de $service..."
        if $follow; then
            bash "$DOCKER_SCRIPT" logs -f "$service"
        else
            bash "$DOCKER_SCRIPT" logs --tail=50 "$service"
        fi
    else
        info "Mostrando logs de todos los servicios..."
        if $follow; then
            bash "$DOCKER_SCRIPT" logs -f
        else
            bash "$DOCKER_SCRIPT" logs --tail=20
        fi
    fi
}

# Función para mostrar métricas detalladas usando docker.sh
show_detailed_metrics() {
    info "Métricas Detalladas"
    echo "======================="
    
    echo
    info "Estado de Contenedores:"
    bash "$DOCKER_SCRIPT" ps
    
    echo
    info "Uso de Recursos Docker:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || warning "No se pudo obtener stats de Docker"
    
    echo
    info "Imágenes Construidas:"
    bash "$DOCKER_SCRIPT" images
    
    echo
    info "Espacio en Disco Docker:"
    docker system df 2>/dev/null || warning "No se pudo obtener info de disco"
}

# Función para probar circuit breaker
test_circuit_breaker() {
    if [[ -f "./cb-test.sh" ]]; then
        info "Ejecutando pruebas de Circuit Breaker..."
        bash ./cb-test.sh
    else
        warning "cb-test.sh no encontrado. Ejecuta desde el directorio raíz."
    fi
}

# Función para mostrar ayuda
show_help() {
    cat << EOF
Script de Monitor para Microservicios

Uso: $0 [opciones] [servicio]

Opciones:
  -h, --help          Mostrar esta ayuda
  -c, --continuous    Monitoreo continuo (cada ${MONITOR_INTERVAL}s)
  -l, --logs [svc]    Mostrar logs (agrega -f para seguir)
  -m, --metrics       Mostrar métricas detalladas
  -t, --test-cb       Probar circuit breaker
  --alert-threshold N Establecer umbral de alertas (default: $ALERT_THRESHOLD)

Ejemplos:
  $0                  Verificar estado actual
  $0 -c               Monitoreo continuo
  $0 -l auth-api      Ver logs de auth-api
  $0 -l -f todos      Ver logs de todos-api siguiendo
  $0 -m               Ver métricas detalladas
  $0 -t               Probar circuit breaker

EOF
}

# Parsear argumentos
CONTINUOUS=false
SHOW_LOGS=false
FOLLOW_LOGS=false
SHOW_METRICS=false
TEST_CB=false
LOG_SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--continuous)
            CONTINUOUS=true
            shift
            ;;
        -l|--logs)
            SHOW_LOGS=true
            if [[ $# -gt 1 && ! $2 =~ ^- ]]; then
                LOG_SERVICE="$2"
                shift
            fi
            shift
            ;;
        -f|--follow)
            FOLLOW_LOGS=true
            shift
            ;;
        -m|--metrics)
            SHOW_METRICS=true
            shift
            ;;
        -t|--test-cb)
            TEST_CB=true
            shift
            ;;
        --alert-threshold)
            ALERT_THRESHOLD="$2"
            shift 2
            ;;
        -*)
            error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
        *)
            # Servicio específico
            if [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                LOG_SERVICE="$1"
                SHOW_LOGS=true
            else
                error "Servicio inválido: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Ejecutar funciones según opciones
if $SHOW_METRICS; then
    show_detailed_metrics
    exit 0
fi

if $TEST_CB; then
    test_circuit_breaker
    exit 0
fi

if $SHOW_LOGS; then
    show_logs "$LOG_SERVICE" "$FOLLOW_LOGS"
    exit 0
fi

# Monitoreo principal
if $CONTINUOUS; then
    info "Iniciando monitoreo continuo (intervalo: ${MONITOR_INTERVAL}s, Ctrl+C para salir)"
    echo "Presiona Ctrl+C para detener..."
    echo
    
    while true; do
        show_all_status
        sleep "$MONITOR_INTERVAL"
        echo
    done
else
    show_all_status
fi