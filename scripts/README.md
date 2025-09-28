# Scripts de Automatización - Microservicios

Este directorio contiene todos los scripts de automatización para gestionar el proyecto de microservicios, incluyendo despliegue, monitoreo, limpieza y testing.

## Scripts Disponibles

### Scripts Principales


| Script | Descripción | Uso Principal |
|--------|-------------|---------------|
| [`docker.sh`](docker.sh) | **Script avanzado de Docker** - Gestión completa de contenedores | Construcción, despliegue, logs, aliases |
| [`setup.sh`](setup.sh) | **Verificación de entorno** - Prerequisites y dependencias | Antes de cualquier despliegue |
| [`deploy.sh`](deploy.sh) | **Despliegue inteligente** - Construye y despliega servicios | Despliegue principal |
| [`monitor.sh`](monitor.sh) | **Monitoreo de servicios** - Salud y métricas en tiempo real | Vigilancia continua |
| [`cleanup.sh`](cleanup.sh) | **Limpieza del sistema** - Contenedores, imágenes, volúmenes | Mantenimiento |

### Scripts de Testing

| Script | Descripción | Uso Principal |
|--------|-------------|---------------|
| [`cb-test.sh`](cb-test.sh) | **Testing de Circuit Breaker** - Pruebas de resiliencia | Validación de patrones |

## Flujo de Trabajo Recomendado

### Desarrollo Diario

```bash
# 1. Verificar entorno (primera vez o cambios)
./scripts/setup.sh

# 2. Desplegar servicios
./scripts/deploy.sh

# 3. Monitorear durante desarrollo
./scripts/monitor.sh -c

# 4. Limpiar al finalizar
./scripts/cleanup.sh
```

### Construcción y Despliegue Avanzado

```bash
# Construir solo imágenes
./scripts/deploy.sh --images-only

# Desplegar con reconstrucción completa
./scripts/deploy.sh --rebuild

# Usar imágenes versionadas
./scripts/deploy.sh --tag v1.0.0
```

### Monitoreo y Debugging

```bash
# Monitoreo continuo
./scripts/monitor.sh -c

# Logs de servicios específicos
./scripts/monitor.sh -l auth-api -f

# Métricas detalladas
./scripts/monitor.sh -m

# Testing de circuit breaker
./scripts/monitor.sh -t
```

### Gestión de Contenedores (Docker.sh)

```bash
# Acciones principales
./scripts/docker.sh up           # Desplegar
./scripts/docker.sh stop         # Detener
./scripts/docker.sh logs -f      # Ver logs
./scripts/docker.sh ps           # Estado

# Construcción avanzada
./scripts/docker.sh build-images --service all --tag latest
./scripts/docker.sh build-images --service auth-api --no-cache

# Alias convenientes
./scripts/docker.sh install-alias  # Instalar alias 'ms'
```

## Detalles de Cada Script

### `docker.sh` - Gestión Avanzada de Docker

**Funciones principales:**
- Gestión completa de Docker Compose
- Construcción individual de imágenes
- Sistema de aliases (ms)
- Detección automática de Docker Compose v1/v2
- Alias para servicios y acciones

**Ejemplos:**
```bash
./scripts/docker.sh up                    # Desplegar todo
./scripts/docker.sh build frontend       # Construir solo frontend
./scripts/docker.sh logs -f auth-api     # Seguir logs
./scripts/docker.sh clean                # Limpieza profunda
```

### `setup.sh` - Verificación de Entorno

**Verifica:**
- Docker y Docker Compose instalados
- Lenguajes necesarios (Go, Node.js, Java, Python)
- Conectividad de red
- Archivos del proyecto
- Configuración del script docker.sh

**Ejemplos:**
```bash
./scripts/setup.sh              # Verificación completa
# Responde 'y' para limpiar si es necesario
```

### `deploy.sh` - Despliegue Inteligente

**Opciones de despliegue:**
- Despliegue completo con construcción
- Despliegue con imágenes preconstruidas
- Solo construcción de imágenes
- Reconstrucción desde cero

**Ejemplos:**
```bash
./scripts/deploy.sh                    # Despliegue normal
./scripts/deploy.sh --rebuild          # Reconstruir imágenes
./scripts/deploy.sh --images-only      # Solo imágenes
./scripts/deploy.sh --tag v1.0.0      # Versión específica
```

### `monitor.sh` - Monitoreo de Servicios

**Funciones:**
- Verificación de salud HTTP/TCP
- Monitoreo continuo con alertas
- Métricas específicas por servicio
- Logs en tiempo real
- Testing de circuit breaker

**Ejemplos:**
```bash
./scripts/monitor.sh                   # Estado actual
./scripts/monitor.sh -c               # Monitoreo continuo
./scripts/monitor.sh -l auth-api      # Logs de auth-api
./scripts/monitor.sh -m               # Métricas detalladas
./scripts/monitor.sh -t               # Test circuit breaker
```

### `cleanup.sh` - Limpieza del Sistema

**Opciones de limpieza:**
- Limpieza completa (todo)
- Solo contenedores parados
- Solo imágenes preconstruidas
- Solo archivos temporales del proyecto
- Solo sistema Docker

**Ejemplos:**
```bash
./scripts/cleanup.sh                  # Menú interactivo
./scripts/cleanup.sh -a              # Limpieza completa
./scripts/cleanup.sh -s              # Sistema Docker
./scripts/cleanup.sh -p              # Archivos proyecto
```

### `cb-test.sh` - Testing de Circuit Breaker

**Pruebas de resiliencia:**
- Testing de auth-api circuit breaker
- Testing de todos-api circuit breaker
- Simulación de fallos
- Verificación de recuperación

**Ejemplo:**
```bash
./scripts/cb-test.sh                 # Ejecutar pruebas completas
```

## Configuración Inicial

### Hacer Scripts Ejecutables

```bash
chmod +x scripts/*.sh
```

### Instalar Alias (Opcional)

```bash
# Instalar alias persistente 'ms'
./scripts/docker.sh install-alias

# O activar en sesión actual
eval "$(./scripts/docker.sh alias-activate)"

# Usar alias
ms up
ms logs -f auth
ms build-images --service all
```

## Arquitectura de Servicios

Los scripts gestionan estos servicios:

| Servicio | Puerto | Tecnología | Descripción |
|----------|--------|------------|-------------|
| `frontend` | 3000 | Vue.js | Interfaz de usuario |
| `auth-api` | 8000 | Go | Autenticación JWT |
| `users-api` | 8083 | Java/Spring | Gestión de usuarios |
| `todos-api` | 8082 | Node.js | API de TODOs con cache-aside |
| `log-message-processor` | - | Python | Procesador de logs Redis |
| `redis-todo` | 6379 | Redis | Cache y cola de mensajes |
| `zipkin` | 9411 | Zipkin | Trazabilidad distribuida |

## Patrones Implementados

- **Cache-aside**: `todos-api` con Redis (TTL: 60s)
- **Circuit Breaker**: `auth-api` (configurable)
- **Distributed Tracing**: Zipkin para todos los servicios
- **Health Checks**: Endpoints `/health` en APIs principales

## Solución de Problemas

### Problemas Comunes

**"Permission denied" en scripts:**
```bash
chmod +x scripts/*.sh
```

**"Docker no encontrado":**
```bash
./scripts/setup.sh  # Verificará instalación
```

**Servicios no responden:**
```bash
./scripts/monitor.sh -c  # Monitoreo continuo
./scripts/monitor.sh -l [servicio]  # Logs específicos
```

**Imágenes no se construyen:**
```bash
./scripts/deploy.sh --rebuild  # Reconstruir desde cero
```

### Logs y Debugging

```bash
# Logs de todos los servicios
./scripts/docker.sh logs

# Logs de un servicio específico
./scripts/docker.sh logs auth-api

# Seguir logs en tiempo real
./scripts/docker.sh logs -f todos-api

# Estado detallado
./scripts/docker.sh ps
```
