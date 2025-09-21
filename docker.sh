#!/usr/bin/env bash

set -Eeuo pipefail

# Directorios del proyecto
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd)"

# Resolver ubicación de docker-compose.yml: primero junto al script, luego en el padre
if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
  COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
elif [[ -f "${ROOT_DIR}/docker-compose.yml" ]]; then
  COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
else
  echo "No se encontró docker-compose.yml en: ${SCRIPT_DIR} ni en ${ROOT_DIR}" >&2
  exit 1
fi

# Detectar comando de Docker Compose (v1 o v2)
if command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker-compose)
elif docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
else
  echo "Docker Compose no está instalado o no es accesible en PATH." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Uso:
  docker.sh <accion> [servicio]

Acciones principales:
  create       Crea los contenedores sin iniciarlos
  build        Construye las imágenes
  up           Levanta los servicios en segundo plano
  stop         Detiene los servicios (sin eliminar contenedores)

Acciones útiles adicionales:
  down         Detiene y elimina contenedores/redes
  restart      Reinicia servicios
  logs         Muestra logs (agrega -f para seguir)
  ps           Muestra estado de contenedores
  clean        down -v --remove-orphans (limpieza profunda)

Construcción avanzada de imágenes (sin docker compose):
  build-images [--service <nombre>|all] [--tag <tag>] [--no-cache]
    Construye imágenes docker por servicio con nombre microservices-<servicio>:<tag>
  images
    Lista las imágenes construidas (prefijo microservices-)
  install-alias
    Instala el alias persistente 'ms' sin ejecutar ninguna otra acción
  alias-activate
    Imprime el alias para activarlo en la sesión actual (usar con eval)
  bootstrap-alias
    Instala el alias y emite el alias listo para eval en esta sesión

Atajos/Alias:
  Acciones: u=up, b=build, bi=build-images, i=images, s=stop, d=down,
            r=restart, l=logs, p=ps, c=clean, cr=create, h=help
  Servicios: users|user|ua -> users-api
             auth|a -> auth-api
             todos|todo|t -> todos-api
             lp|log|logproc|log-processor|log-message -> log-message-processor (compose)
             lp|log|logproc|log-processor|log-message -> log-processor (build-images)
             fe|front|ui|web -> frontend

Notas:
  - [servicio] es opcional. Si se omite, la acción aplica a todos.
  - Requiere Docker y Docker Compose instalados.
  - En el primer uso, se instalará un alias persistente 'ms' que apunta a este script.
  - Ejemplos:
      bash docker.sh build
      bash docker.sh up
      bash docker.sh stop
      bash docker.sh build frontend
      bash docker.sh logs -f todos-api
      bash docker.sh build-images --service all --tag latest
      bash docker.sh build-images --service users-api --tag v1.0.0 --no-cache
      # Con alias
      bash docker.sh u
      bash docker.sh l -f todos
      bash docker.sh bi --service auth --tag v2 --no-cache
      # Activar alias en la sesión actual (sin abrir nueva terminal)
      eval "$(bash docker.sh alias-activate)"
      # Instalar y activar en un solo paso
      eval "$(bash docker.sh bootstrap-alias)"
EOF
}

ACTION="${1:-help}"
shift || true

# Permitir pasar flags/servicio posteriores tal cual
EXTRA_ARGS=("$@")

# Alias de acciones y servicios
declare -A ACTION_ALIASES=(
  [u]=up [b]=build [bi]=build-images [i]=images [s]=stop [d]=down [r]=restart [l]=logs [p]=ps [c]=clean [cr]=create [h]=help
)

# Alias de servicios para docker compose (nombres tal como en docker-compose.yml)
declare -A COMPOSE_SERVICE_ALIASES=(
  [users]=users-api [user]=users-api [ua]=users-api [usersapi]=users-api
  [auth]=auth-api [a]=auth-api [authapi]=auth-api
  [todos]=todos-api [todo]=todos-api [t]=todos-api [todosapi]=todos-api
  [lp]=log-message-processor [log]=log-message-processor [logproc]=log-message-processor [log-processor]=log-message-processor [log-message]=log-message-processor
  [fe]=frontend [front]=frontend [ui]=frontend [web]=frontend
)

# Alias de servicios para build-images (claves esperadas por SERVICE_TO_CONTEXT)
declare -A IMAGE_SERVICE_ALIASES=(
  [users]=users-api [user]=users-api [ua]=users-api [usersapi]=users-api
  [auth]=auth-api [a]=auth-api [authapi]=auth-api
  [todos]=todos-api [todo]=todos-api [t]=todos-api [todosapi]=todos-api
  [lp]=log-processor [log]=log-processor [logproc]=log-processor [log-processor]=log-processor [log-message]=log-processor [log-message-processor]=log-processor
  [fe]=frontend [front]=frontend [ui]=frontend [web]=frontend
)

normalize_action() {
  local act="$1"
  echo "${ACTION_ALIASES[$act]:-$act}"
}

normalize_compose_arg_tokens() {
  local -a out=()
  for tok in "${EXTRA_ARGS[@]}"; do
    if [[ "$tok" == -* ]]; then
      out+=("$tok")
    else
      out+=("${COMPOSE_SERVICE_ALIASES[$tok]:-$tok}")
    fi
  done
  EXTRA_ARGS=("${out[@]}")
}

normalize_image_service() {
  local svc="$1"
  if [[ "$svc" == "all" ]]; then
    echo "$svc"
    return 0
  fi
  echo "${IMAGE_SERVICE_ALIASES[$svc]:-$svc}"
}

# Normalizar acción y posibles alias de servicios en argumentos
ACTION="$(normalize_action "$ACTION")"
normalize_compose_arg_tokens

compose() {
  "${DOCKER_COMPOSE[@]}" -f "${COMPOSE_FILE}" "$@"
}

docker_available() {
  if command -v docker >/dev/null 2>&1; then
    docker --version >/dev/null 2>&1
  else
    return 1
  fi
}

ensure_persistent_alias() {
  # Configuración
  local alias_name="ms"
  local script_path
  script_path="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"

  # Detectar archivo de perfil según shell (manejo de Git Bash)
  local shell_name
  shell_name="$(basename -- "${SHELL:-bash}")"
  local profile_file
  local bash_rc="${HOME}/.bashrc"
  local bash_profile="${HOME}/.bash_profile"
  local is_git_bash="false"
  if [[ "${MSYSTEM:-}" != "" ]] || uname -s 2>/dev/null | grep -qi "mingw\|msys\|cygwin"; then
    is_git_bash="true"
  fi
  case "$shell_name" in
    zsh)
      profile_file="${HOME}/.zshrc" ;;
    bash|sh|*)
      if [[ "$is_git_bash" == "true" ]]; then
        profile_file="$bash_rc"
        # Asegurar que ~/.bash_profile cargue ~/.bashrc
        [[ -f "$bash_profile" ]] || touch "$bash_profile" 2>/dev/null || true
        if ! grep -q "^[[:space:]]*\.\s*\$HOME/\.bashrc\>" "$bash_profile" 2>/dev/null \
           && ! grep -q "^[[:space:]]*source\s*\$HOME/\.bashrc\>" "$bash_profile" 2>/dev/null; then
          {
            echo "" ;
            echo "# Cargar alias desde ~/.bashrc (agregado automáticamente)" ;
            echo ". \"$bash_rc\"" ;
          } >> "$bash_profile" 2>/dev/null || true
        fi
      else
        profile_file="$bash_rc"
      fi ;;
  esac

  if [[ ! -f "${profile_file}" ]]; then
    touch "${profile_file}" 2>/dev/null || true
  fi

  if [[ -f "${profile_file}" ]] && grep -q "^alias ${alias_name}=" "${profile_file}" 2>/dev/null; then
    return 0
  fi

  # Añadir alias de forma idempotente
  local marker="# Alias persistente para microservice-app (auto)"
  local alias_line="alias ${alias_name}='bash \"${script_path}\"'"
  {
    echo "" ;
    echo "${marker}" ;
    echo "${alias_line}" ;
  } >> "${profile_file}" 2>/dev/null || true

  echo "⚙️  Alias persistente instalado: ${alias_name} -> ${script_path}"
  echo "➡️  Abre una nueva terminal o ejecuta: source \"${profile_file}\""
}

alias_activate_output() {
  local alias_name="ms"
  local script_path
  script_path="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
  echo "alias ${alias_name}='bash \"${script_path}\"'"
}

bootstrap_alias() {
  ensure_persistent_alias || true
  alias_activate_output
}

list_built_images() {
  if ! docker_available; then
    echo "Docker no está disponible." >&2
    return 1
  fi
  docker images --filter 'reference=microservices-*' \
    --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'
}

# Instalar alias persistente en primer uso (idempotente)
ensure_persistent_alias || true

build_images_action() {
  if ! docker_available; then
    echo "❌ Docker no está disponible o no está instalado." >&2
    exit 1
  fi

  # Servicios soportados y sus contextos
  declare -A SERVICE_TO_CONTEXT
  SERVICE_TO_CONTEXT=(
    [users-api]="${ROOT_DIR}/users-api"
    [auth-api]="${ROOT_DIR}/auth-api"
    [todos-api]="${ROOT_DIR}/todos-api"
    [log-processor]="${ROOT_DIR}/log-message-processor"
    [frontend]="${ROOT_DIR}/frontend"
  )
  # Orden estable de construcción
  local SERVICE_ORDER=(users-api auth-api todos-api log-processor frontend)

  local SERVICE="all"
  local TAG="latest"
  local NO_CACHE="false"

  # Reinyectar argumentos para esta sub-acción
  set -- "${EXTRA_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --service|-s)
        SERVICE="$2"; shift 2 ;;
      --tag|-t)
        TAG="$2"; shift 2 ;;
      --no-cache)
        NO_CACHE="true"; shift ;;
      --help|-h)
        echo "Uso: docker.sh build-images [--service <nombre>|all] [--tag <tag>] [--no-cache]"; return 0 ;;
      *)
        echo "Argumento desconocido para build-images: $1" >&2; return 1 ;;
    esac
  done

  local build_args_base=(build)
  if [[ "${NO_CACHE}" == "true" ]]; then
    build_args_base+=(--no-cache)
  fi

  local total=0
  local ok=0

  echo "==========================================="
  echo "Iniciando construcción de imágenes Docker"
  echo "==========================================="
  echo "Servicio: ${SERVICE}"
  echo "Tag: ${TAG}"
  echo "No Cache: ${NO_CACHE}"
  echo "==========================================="

  build_one() {
    local svc="$1"
    local ctx="$2"
    local tag="$3"
    echo "==========================================="
    echo "Construyendo imagen: ${svc}"
    echo "Contexto: ${ctx}"
    echo "Tag: ${tag}"
    echo "==========================================="

    if [[ ! -d "${ctx}" ]]; then
      echo "⚠️  Advertencia: No se encontró el directorio ${ctx}" >&2
      return 1
    fi

    local args=( "${build_args_base[@]}" -t "microservices-${svc}:${tag}" "${ctx}" )
    if ! docker "${args[@]}"; then
      echo "❌ Error al construir la imagen: ${svc}" >&2
      return 1
    fi
    echo "✅ Imagen construida exitosamente: microservices-${svc}:${tag}"
    return 0
  }

  if [[ "${SERVICE}" == "all" ]]; then
    for s in "${SERVICE_ORDER[@]}"; do
      (( total++ ))
      if build_one "$s" "${SERVICE_TO_CONTEXT[$s]}" "${TAG}"; then
        (( ok++ ))
      fi
    done
  else
    if [[ -z "${SERVICE_TO_CONTEXT[$SERVICE]:-}" ]]; then
      echo "❌ Error: Servicio '${SERVICE}' no reconocido." >&2
      echo "Servicios disponibles: ${SERVICE_ORDER[*]}" >&2
      exit 1
    fi
    total=1
    if build_one "${SERVICE}" "${SERVICE_TO_CONTEXT[$SERVICE]}" "${TAG}"; then
      ok=1
    fi
  fi

  echo "==========================================="
  echo "Resumen de construcción"
  echo "==========================================="
  echo "Imágenes construidas exitosamente: ${ok} de ${total}"
  if [[ ${ok} -eq ${total} ]]; then
    echo "✅ Todas las imágenes se construyeron correctamente"
  else
    echo "⚠️  Algunas imágenes fallaron en la construcción"
  fi
  echo
  echo "Imágenes construidas (prefijo microservices-):"
  list_built_images || true
}

case "${ACTION}" in
  create)
    compose create "${EXTRA_ARGS[@]}"
    ;;
  build)
    compose build "${EXTRA_ARGS[@]}"
    ;;
  build-images)
    build_images_action
    ;;
  install-alias)
    ensure_persistent_alias
    ;;
  alias-activate)
    alias_activate_output
    ;;
  bootstrap-alias)
    bootstrap_alias
    ;;
  up)
    # --build por conveniencia para construir si hay cambios
    compose up -d --build "${EXTRA_ARGS[@]}"
    ;;
  stop)
    compose stop "${EXTRA_ARGS[@]}"
    ;;
  down)
    compose down "${EXTRA_ARGS[@]}"
    ;;
  restart)
    compose restart "${EXTRA_ARGS[@]}"
    ;;
  logs)
    compose logs "${EXTRA_ARGS[@]}"
    ;;
  ps)
    compose ps "${EXTRA_ARGS[@]}"
    ;;
  clean)
    compose down -v --remove-orphans
    ;;
  images)
    list_built_images
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Acción desconocida: ${ACTION}" >&2
    echo
    usage
    exit 1
    ;;
esac


