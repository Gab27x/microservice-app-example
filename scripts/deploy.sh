#!/usr/bin/env bash
set -euo pipefail

# Script de Deploy para Microservicios
# Construye y despliega todos los servicios usando docker.sh

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

# Servicios principales
SERVICES=("redis-todo" "zipkin" "users-api" "auth-api" "todos-api" "log-message-processor" "frontend")

# Función para esperar a que un servicio esté listo
wait_for_service() {
    local service="$1"
    local host="${2:-localhost}"
    local port="$3"
    local timeout="${4:-30}"
    local path="${5:-/health}"
    
    info "Esperando a $service en $host:$port$path..."
    
    local waited=0
    while [ $waited -lt $timeout ]; do
        if curl -fs --max-time 3 "http://$host:$port$path" >/dev/null 2>&1; then
            success "$service está listo"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    warning "$service no respondió en ${timeout}s"
    return 1
}

# Función para verificar estado de servicios
check_services_status() {
    info "Verificando estado de servicios..."
    
    local all_running=true
    
    # Verificar contenedores Docker
    for service in "${SERVICES[@]}"; do
        if bash "$DOCKER_SCRIPT" ps | grep -q "$service"; then
            success "✓ $service está corriendo"
        else
            error "✗ $service no está corriendo"
            all_running=false
        fi
    done
    
    if $all_running; then
        success "Todos los servicios están corriendo"
    else
        warning "Algunos servicios no están corriendo correctamente"
    fi
    
    return $([ "$all_running" = true ] && echo 0 || echo 1)
}

# Función para mostrar información del despliegue
show_deployment_info() {
    echo
    success "Despliegue completado exitosamente!"
    echo
    info "Servicios disponibles:"
    info "  • Frontend (Vue.js):     http://localhost:3000"
    info "  • Auth API (Go):         http://localhost:8000"
    info "  • Users API (Java):      http://localhost:8083"
    info "  • Todos API (Node.js):   http://localhost:8082"
    info "  • Zipkin (Tracing):      http://localhost:9411"
    info "  • Redis:                 localhost:6379"
    echo
    info "Circuit Breaker test:     ./cb-test.sh"
    echo
    info "Comandos útiles con docker.sh:"
    info "  • Ver logs:              ./docker.sh logs -f [servicio]"
    info "  • Estado:                ./docker.sh ps"
    info "  • Reiniciar:             ./docker.sh restart [servicio]"
    info "  • Detener:               ./docker.sh stop"
    info "  • Limpiar:               ./docker.sh clean"
    echo
    info "O usar el alias 'ms' después de instalarlo:"
    info "  • Instalar alias:        ./docker.sh install-alias"
    info "  • Usar:                  ms logs -f todos"
}

# Función para desplegar con imágenes preconstruidas
deploy_with_prebuild() {
    local tag="${1:-latest}"
    
    info "Desplegando con imágenes preconstruidas (tag: $tag)..."
    
    # Verificar si las imágenes existen
    local missing_images=()
    for service in users-api auth-api todos-api log-processor frontend; do
        if ! docker images "microservices-$service:$tag" | grep -q "$tag"; then
            missing_images+=("$service")
        fi
    done
    
    if [ ${#missing_images[@]} -gt 0 ]; then
        warning "Imágenes faltantes: ${missing_images[*]}"
        read -p "¿Quieres construir las imágenes faltantes? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            info "Construyendo imágenes faltantes..."
            for service in "${missing_images[@]}"; do
                bash "$DOCKER_SCRIPT" build-images --service "$service" --tag "$tag"
            done
        else
            info "Usando Docker Compose normal..."
            bash "$DOCKER_SCRIPT" up
            return
        fi
    fi
    
    # Usar Docker Compose con imágenes preconstruidas
    info "Levantando servicios..."
    bash "$DOCKER_SCRIPT" up
}

# Función principal de deploy
deploy_services() {
    info "Iniciando despliegue de microservicios"
    echo "========================================"
    
    # Verificar que docker.sh existe y funciona
    if [[ ! -x "$DOCKER_SCRIPT" ]]; then
        error "docker.sh no encontrado o no ejecutable"
        exit 1
    fi
    
    # Detener servicios existentes
    info "Deteniendo servicios existentes..."
    bash "$DOCKER_SCRIPT" down >/dev/null 2>&1 || true
    
    # Preguntar tipo de despliegue
    echo
    info "Opciones de despliegue:"
    info "1) Despliegue completo con construcción (--build)"
    info "2) Despliegue con imágenes preconstruidas"
    info "3) Solo construir imágenes (sin desplegar)"
    echo
    read -p "Selecciona opción (1-3) [1]: " -n 1 -r
    echo
    local choice="${REPLY:-1}"
    
    case $choice in
        1)
            info "Desplegando con construcción automática..."
            bash "$DOCKER_SCRIPT" up
            ;;
        2)
            read -p "Tag de imágenes [latest]: " tag
            tag="${tag:-latest}"
            deploy_with_prebuild "$tag"
            ;;
        3)
            info "Solo construyendo imágenes..."
            bash "$DOCKER_SCRIPT" build-images --service all
            echo
            info "Imágenes construidas. Para desplegar usa: ./deploy.sh"
            exit 0
            ;;
        *)
            error "Opción inválida"
            exit 1
            ;;
    esac
    
    # Esperar un poco para inicialización
    info "Esperando inicialización de servicios..."
    sleep 5
    
    # Verificar estado inicial
    if ! check_services_status; then
        warning "Algunos servicios pueden no estar listos aún"
    fi
    
    # Esperar servicios críticos
    echo
    info "Esperando servicios críticos..."
    
    # Esperar Redis (TCP)
    if timeout 30 bash -c "</dev/tcp/localhost/6379" 2>/dev/null; then
        success "Redis está listo"
    else
        warning "Redis puede no estar listo aún"
    fi
    
    # Esperar Zipkin
    wait_for_service "Zipkin" "localhost" "9411" 30 || warning "Zipkin puede no estar listo aún"
    
    # Esperar users-api
    wait_for_service "users-api" "localhost" "8083" 60 || warning "users-api puede no estar listo aún"
    
    # Esperar auth-api
    wait_for_service "auth-api" "localhost" "8000" 30 || warning "auth-api puede no estar listo aún"
    
    # Esperar todos-api
    wait_for_service "todos-api" "localhost" "8082" 30 || warning "todos-api puede no estar listo aún"
    
    # Frontend
    wait_for_service "frontend" "localhost" "3000" 30 || warning "frontend puede no estar listo aún"
    
    # Mostrar información final
    show_deployment_info
}

# Función para mostrar ayuda
show_help() {
    cat << EOF
Script de Despliegue para Microservicios

Uso: $0 [opciones]

Opciones:
  -h, --help          Mostrar esta ayuda
  --rebuild           Reconstruir todas las imágenes desde cero
  --tag TAG           Usar imágenes con tag específico
  --images-only       Solo construir imágenes, no desplegar

Ejemplos:
  $0                  Desplegar normalmente
  $0 --rebuild        Reconstruir y desplegar
  $0 --tag v1.0.0     Usar imágenes versionadas
  $0 --images-only    Solo construir imágenes

EOF
}

# Parsear argumentos
REBUILD=false
IMAGES_ONLY=false
TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --rebuild)
            REBUILD=true
            shift
            ;;
        --images-only)
            IMAGES_ONLY=true
            shift
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        *)
            error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Ejecutar despliegue
if $IMAGES_ONLY; then
    info "Construyendo imágenes..."
    if $REBUILD; then
        bash "$DOCKER_SCRIPT" build-images --service all --no-cache
    else
        bash "$DOCKER_SCRIPT" build-images --service all
    fi
    success "Imágenes construidas"
else
    deploy_services
fi