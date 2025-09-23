#!/usr/bin/env bash

# Script de Setup para Microservicios
# Verifica dependencias y prepara el entorno

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_SCRIPT="${SCRIPT_DIR}/docker.sh"

say() { printf "%s\n" "$*" >&2; }
success() { printf "${GREEN}✓ %s${NC}\n" "$*" >&2; }
error() { printf "${RED}✗ %s${NC}\n" "$*" >&2; }
warning() { printf "${YELLOW}⚠ %s${NC}\n" "$*" >&2; }
info() { printf "${BLUE}ℹ %s${NC}\n" "$*" >&2; }

# Función para verificar si Docker está corriendo
check_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        error "Docker no está corriendo. Por favor inicia Docker primero."
        return 1
    fi
    return 0
}

# Función para verificar Docker Compose
check_docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        success "Docker Compose v1 detectado"
        return 0
    elif docker compose version >/dev/null 2>&1; then
        success "Docker Compose v2 (plugin) detectado"
        return 0
    else
        error "Docker Compose no está disponible"
        return 1
    fi
}

# Función para verificar archivos necesarios
check_project_files() {
    info "Verificando archivos del proyecto..."

    local required_files=(
        "docker-compose.yml"
        "scripts/docker.sh"
        "auth-api/Dockerfile"
        "users-api/Dockerfile"
        "todos-api/Dockerfile"
        "frontend/Dockerfile"
        "log-message-processor/Dockerfile"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            success "$file encontrado"
        else
            error "$file no encontrado"
            return 1
        fi
    done

    return 0
}

# Función para verificar configuración del docker.sh
check_docker_script() {
    info "Verificando configuración del script docker.sh..."

    if [[ -x "$DOCKER_SCRIPT" ]]; then
        success "docker.sh es ejecutable"
        success "docker.sh configurado correctamente"
    else
        error "docker.sh no es ejecutable"
        chmod +x "$DOCKER_SCRIPT"
        success "Permisos de ejecución añadidos a docker.sh"
    fi
}

# Función para verificar dependencias de lenguajes
check_language_deps() {
    info "Verificando dependencias de lenguajes..."

    # Node.js para todos-api y frontend
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node --version 2>/dev/null)
        success "Node.js: $node_version"
    else
        warning "Node.js no encontrado (necesario para todos-api y frontend)"
    fi

    # Go para auth-api
    if command -v go >/dev/null 2>&1; then
        local go_version
        go_version=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
        success "Go: $go_version"
    else
        warning "Go no encontrado (necesario para auth-api)"
    fi

    # Java para users-api
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        success "Java: $java_version"
    fi

    # Python para log-message-processor
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        success "Python3: $python_version"
    fi
}

# Función para verificar conectividad de red
check_network() {
    info "Verificando conectividad de red..."

    if curl -s --max-time 5 https://registry-1.docker.io >/dev/null 2>&1; then
        success "Conexion a Docker Hub OK"
    else
        warning "No se puede conectar a Docker Hub (puede ser normal si usas registry local)"
    fi

    if curl -s --max-time 5 https://registry.npmjs.org >/dev/null 2>&1; then
        success "Conexion a NPM OK"
    else
        warning "No se puede conectar a NPM"
    fi
}

# Función para limpiar contenedores e imágenes huérfanas
cleanup_docker() {
    info "Limpiando contenedores e imágenes huérfanas..."

    # Usar docker.sh para limpieza
    if bash "$DOCKER_SCRIPT" clean >/dev/null 2>&1; then
        success "Limpieza completada con docker.sh"
    else
        # Fallback manual
        docker ps -a -q -f status=exited | xargs docker rm -f >/dev/null 2>&1 || true
        docker images -f "dangling=true" -q | xargs docker rmi -f >/dev/null 2>&1 || true
        success "Limpieza manual completada"
    fi
}

# Función principal
main() {
    echo
    info "Verificacion del entorno para Microservicios"
    echo "==============================================="

    local checks_passed=0
    local total_checks=0

    # Verificar archivos del proyecto
    ((total_checks++))
    if check_project_files; then
        ((checks_passed++))
    fi

    # Verificar Docker
    ((total_checks++))
    if check_docker_running; then
        ((checks_passed++))
    fi

    # Verificar Docker Compose
    ((total_checks++))
    if check_docker_compose; then
        ((checks_passed++))
    fi

    # Verificar script docker.sh
    ((total_checks++))
    if check_docker_script; then
        ((checks_passed++))
    fi

    # Verificar dependencias de lenguajes
    check_language_deps

    # Verificar conectividad
    check_network

    echo
    info "Resultado: $checks_passed/$total_checks verificaciones principales pasaron"

    if [ "$checks_passed" -eq "$total_checks" ]; then
        success "¡Entorno listo para desplegar microservicios!"
        echo
        info "Comandos disponibles:"
        info "  • Desplegar:     ./scripts/deploy.sh"
        info "  • Monitorear:     ./scripts/monitor.sh"
        info "  • Limpiar:        ./scripts/cleanup.sh"
        info "  • Docker alias:   ms (después de instalar)"
        echo
        info "Para instalar alias persistente: ./scripts/docker.sh install-alias"
    else
        error "Hay problemas que resolver antes de continuar"
        return 1
    fi

    # Preguntar si quiere limpiar Docker
    echo
    read -p "¿Quieres limpiar contenedores e imágenes huérfanas? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_docker
    fi
}

# Ejecutar función principal
main "$@"
