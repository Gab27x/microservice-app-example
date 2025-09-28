#!/usr/bin/env bash
set -euo pipefail

# Script de Cleanup para Microservicios
# Limpia usando docker.sh y opciones avanzadas

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

# Función para confirmar acción destructiva
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    local prompt
    if [ "$default" = "y" ]; then
        prompt=" (Y/n): "
    else
        prompt=" (y/N): "
    fi
    
    read -p "$message$prompt" -n 1 -r
    echo
    
    if [ "$default" = "y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Función para detener servicios usando docker.sh
stop_services() {
    info "Deteniendo servicios..."
    
    if bash "$DOCKER_SCRIPT" ps | grep -q "Up"; then
        bash "$DOCKER_SCRIPT" stop
        success "Servicios detenidos"
    else
        info "No hay servicios corriendo"
    fi
}

# Función para remover contenedores usando docker.sh
remove_containers() {
    info "Removiendo contenedores..."
    
    if bash "$DOCKER_SCRIPT" ps -a | grep -q "Exited\|Created"; then
        # Usar docker compose down para remover contenedores
        bash "$DOCKER_SCRIPT" down
        success "Contenedores removidos"
    else
        info "No hay contenedores para remover"
    fi
}

# Función para remover imágenes
remove_images() {
    local force="$1"
    info "Removiendo imágenes preconstruidas..."
    
    # Remover imágenes microservices-*
    local images_to_remove
    images_to_remove=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^microservices-" || true)
    
    if [ -n "$images_to_remove" ]; then
        info "Imágenes a remover:"
        echo "$images_to_remove"
        
        if [ "$force" = "true" ]; then
            echo "$images_to_remove" | xargs docker rmi -f >/dev/null 2>&1
        else
            echo "$images_to_remove" | xargs docker rmi >/dev/null 2>&1 || warning "Algunas imágenes no pudieron removerse (pueden estar en uso)"
        fi
        success "Imágenes removidas"
    else
        info "No hay imágenes preconstruidas para remover"
    fi
}

# Función para limpiar sistema Docker
system_cleanup() {
    info "Realizando limpieza profunda del sistema Docker..."
    
    # Remover contenedores parados
    local stopped_containers
    stopped_containers=$(docker ps -a -q -f status=exited 2>/dev/null || true)
    if [ -n "$stopped_containers" ]; then
        info "Removiendo contenedores parados..."
        echo "$stopped_containers" | xargs docker rm -f >/dev/null 2>&1
        success "Contenedores parados removidos"
    fi
    
    # Remover imágenes huérfanas
    local dangling_images
    dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
    if [ -n "$dangling_images" ]; then
        info "Removiendo imágenes huérfanas..."
        echo "$dangling_images" | xargs docker rmi -f >/dev/null 2>&1
        success "Imágenes huérfanas removidas"
    fi
    
    # Limpiar caché de builds
    info "Limpiando caché de builds..."
    docker builder prune -f >/dev/null 2>&1 || true
    success "Caché de builds limpiado"
    
    # Limpiar volúmenes no utilizados
    info "Limpiando volúmenes no utilizados..."
    docker volume prune -f >/dev/null 2>&1 || true
    success "Volúmenes no utilizados limpiados"
    
    # Mostrar espacio liberado
    info "Espacio liberado:"
    docker system df 2>/dev/null || warning "No se pudo obtener información de disco"
}

# Función para remover archivos temporales del proyecto
cleanup_project_files() {
    info "Limpiando archivos temporales del proyecto..."
    
    local cleaned=false
    
    # Limpiar node_modules si existen
    if [[ -d "frontend/node_modules" ]]; then
        rm -rf frontend/node_modules
        success "frontend/node_modules removido"
        cleaned=true
    fi
    
    if [[ -d "todos-api/node_modules" ]]; then
        rm -rf todos-api/node_modules
        success "todos-api/node_modules removido"
        cleaned=true
    fi
    
    # Limpiar target de Java
    if [[ -d "users-api/target" ]]; then
        rm -rf users-api/target
        success "users-api/target removido"
        cleaned=true
    fi
    
    # Limpiar __pycache__ de Python
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    if [[ $? -eq 0 ]]; then
        success "Directorios __pycache__ removidos"
        cleaned=true
    fi
    
    if ! $cleaned; then
        info "No hay archivos temporales para limpiar"
    fi
}

# Función para mostrar estado actual
show_current_state() {
    info "Estado actual del sistema:"
    echo "=============================="
    
    echo "Contenedores corriendo:"
    bash "$DOCKER_SCRIPT" ps | grep -v "NAME" || echo "  Ninguno"
    
    echo
    echo "Contenedores parados:"
    docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -v "NAMES" || echo "  Ninguno"
    
    echo
    echo "Imágenes preconstruidas:"
    bash "$DOCKER_SCRIPT" images 2>/dev/null || echo "  Ninguna"
    
    echo
    echo "Imágenes huérfanas:"
    docker images -f "dangling=true" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || echo "  Ninguna"
    
    echo
    echo "Volúmenes:"
    docker volume ls --format "{{.Name}}" 2>/dev/null | grep -v "DRIVER" || echo "  Ninguno"
    
    echo
    echo "Espacio en disco Docker:"
    docker system df 2>/dev/null || warning "No se pudo obtener información"
}

# Función para mostrar ayuda
show_help() {
    cat << EOF
Script de Cleanup para Microservicios

Uso: $0 [opciones]

Opciones:
  -h, --help          Mostrar esta ayuda
  -a, --all           Limpieza completa (servicios, imágenes, sistema)
  -f, --force         Forzar eliminación sin confirmación
  -s, --system        Limpieza del sistema Docker
  -p, --project       Limpiar archivos temporales del proyecto
  --status            Mostrar estado actual sin limpiar

Ejemplos:
  $0                  Menú interactivo de limpieza
  $0 -a               Limpieza completa con confirmaciones
  $0 -a -f            Limpieza completa forzada (sin confirmaciones)
  $0 -s               Limpieza del sistema Docker
  $0 -p               Limpiar archivos del proyecto
  $0 --status         Ver estado actual

EOF
}

# Función principal
main() {
    local all=false
    local force=false
    local system=false
    local project=false
    local status_only=false
    
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                all=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -s|--system)
                system=true
                shift
                ;;
            -p|--project)
                project=true
                shift
                ;;
            --status)
                status_only=true
                shift
                ;;
            *)
                error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Mostrar estado si se pidió
    if $status_only; then
        show_current_state
        exit 0
    fi
    
    # Limpieza del sistema
    if $system; then
        info "Iniciando limpieza del sistema Docker"
        system_cleanup
        exit 0
    fi
    
    # Limpieza de archivos del proyecto
    if $project; then
        info "Iniciando limpieza de archivos del proyecto"
        cleanup_project_files
        exit 0
    fi
    
    # Modo all (limpieza completa)
    if $all; then
        info "Iniciando limpieza completa de microservicios"
        
        if ! $force; then
            echo
            warning "Esta acción removerá TODOS los contenedores, imágenes preconstruidas y limpiará el sistema"
            if ! confirm_action "¿Estás seguro de continuar?"; then
                info "Operación cancelada"
                exit 0
            fi
        fi
        
        stop_services
        remove_containers
        remove_images true
        system_cleanup
        
        success "Limpieza completa finalizada"
        exit 0
    fi
    
    # Modo interactivo (default)
    echo
    info "Script de Limpieza para Microservicios"
    echo "=========================================="
    
    show_current_state
    
    echo
    echo "Opciones de limpieza:"
    echo "1) Detener servicios"
    echo "2) Remover contenedores parados"
    echo "3) Remover imágenes preconstruidas"
    echo "4) Limpiar archivos temporales del proyecto"
    echo "5) Limpieza del sistema Docker"
    echo "6) Limpieza completa (todo lo anterior)"
    echo "7) Cancelar"
    echo
    
    local choice
    read -p "Selecciona una opción (1-7): " -n 1 -r
    echo
    
    case $choice in
        1)
            stop_services
            ;;
        2)
            if confirm_action "¿Remover contenedores parados?"; then
                remove_containers
            fi
            ;;
        3)
            if confirm_action "¿Remover imágenes preconstruidas?"; then
                remove_images false
            fi
            ;;
        4)
            if confirm_action "¿Limpiar archivos temporales del proyecto?"; then
                cleanup_project_files
            fi
            ;;
        5)
            if confirm_action "¿Realizar limpieza del sistema Docker?"; then
                system_cleanup
            fi
            ;;
        6)
            if confirm_action "¿Realizar limpieza COMPLETA?"; then
                stop_services
                remove_containers
                remove_images true
                cleanup_project_files
                system_cleanup
                success "Limpieza completa finalizada"
            fi
            ;;
        7|*)
            info "Operación cancelada"
            ;;
    esac
}

# Ejecutar función principal
main "$@"