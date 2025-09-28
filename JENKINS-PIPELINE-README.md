# 🚀 Jenkins Pipeline para Verificación de Integridad de Microservicios

Este Jenkinsfile está diseñado para conectarse a una máquina virtual (VM) remota donde están desplegados los microservicios y realizar una verificación completa de integridad, similar a los GitHub Actions pero ejecutándose contra una VM real.

## 📋 Prerrequisitos

### Configuración de Jenkins

1. **Plugin de Copy Artifacts**: Para obtener la IP de la VM desde el job de infraestructura
2. **Credenciales configuradas**:
   - `deploy-password`: Password del usuario `deploy` en la VM

### Configuración del Job de Infraestructura

El pipeline depende de que exista un job de infraestructura que:
- Genere un artefacto llamado `droplet.properties`
- Contenga la variable `DROPLET_IP=<IP_DE_LA_VM>`

## 🏗️ Estructura del Pipeline

### Etapas Principales

1. **Obtener IP de VM**: Copia el artefacto con la IP de la VM
2. **Verificar Conectividad VM**: Prueba SSH y Docker en la VM
3. **Health Checks Básicos**: Verifica que todos los servicios respondan
4. **Smoke Test Completo**: Prueba el flujo básico de la aplicación
5. **Pruebas de Integridad** (en paralelo):
   - Test de Retry Pattern
   - Test de Circuit Breaker
   - Test de Rate Limiting
6. **Test Cache Pattern**: Verifica el patrón cache-aside
7. **Verificar Logs y Trazas**: Analiza logs y trazas de Zipkin
8. **Reporte de Estado Final**: Genera reporte completo

### Scripts Auxiliares

| Script | Propósito |
|--------|-----------|
| `jenkins-health-check.sh` | Health check básico de endpoints |
| `jenkins-smoke-test.sh` | Test completo del flujo de la aplicación |
| `jenkins-retry-test.sh` | Test del patrón retry usando WireMock |
| `jenkins-cb-test.sh` | Test del circuit breaker |
| `jenkins-rate-limit-test.sh` | Test de rate limiting |
| `jenkins-cache-test.sh` | Test del patrón cache-aside |
| `jenkins-logs-check.sh` | Análisis de logs y trazas |
| `jenkins-final-report.sh` | Generación de reporte final |

## 🎯 Tests Ejecutados

### 1. Smoke Test
- ✅ Conectividad de servicios
- ✅ Autenticación (login)
- ✅ Operaciones CRUD (TODOs)
- ✅ Frontend funcional
- ✅ Zipkin disponible

### 2. Patrones de Microservicios

#### Retry Pattern
- Simula fallos temporales con WireMock
- Verifica reintentos automáticos
- Confirma recuperación exitosa

#### Circuit Breaker
- Provoca fallos para abrir el circuito
- Verifica estados: Closed → Open → Half-Open → Closed
- Confirma protección contra cascadas de fallos

#### Rate Limiting
- Genera ráfagas de requests
- Verifica respuestas 429 (Too Many Requests)
- Confirma que algunos requests pasan

#### Cache Aside
- Ejecuta tests unitarios de cache
- Verifica conectividad con Redis
- Mide tiempos de respuesta para confirmar cache

### 3. Observabilidad
- **Logs**: Análisis de logs de todos los servicios
- **Trazas**: Verificación de trazas en Zipkin
- **Métricas**: Uso de CPU, memoria y disco
- **Conectividad**: Tests internos entre servicios

## 📊 Reportes Generados

### Archivos de Reporte

- `test-results/final-integrity-report.json`: Reporte completo en JSON
- `test-results/FINAL-REPORT.md`: Reporte legible en Markdown
- `test-results/*-summary.json`: Reportes individuales por test
- `logs/*.log`: Logs de cada servicio

### Métricas de Evaluación

- **Score de Tests**: % de tests que pasaron exitosamente
- **Score de Endpoints**: % de endpoints que responden correctamente
- **Score General**: Promedio de los scores anteriores

#### Estados Posibles

| Score | Estado | Descripción |
|-------|--------|-------------|
| 90-100% | 🟢 EXCELLENT | Sistema funcionando óptimamente |
| 75-89% | 🟡 GOOD | Sistema saludable con problemas menores |
| 50-74% | 🟠 DEGRADED | Problemas significativos |
| 0-49% | 🔴 CRITICAL | Estado crítico, requiere atención inmediata |

## 🚀 Uso

### Configuración del Pipeline

1. Crear un nuevo job de Pipeline en Jenkins
2. Configurar el repositorio Git
3. Ajustar el nombre del proyecto de infraestructura en el Jenkinsfile:
   ```groovy
   projectName: 'tu-proyecto-infraestructura'
   ```
4. Configurar las credenciales necesarias

### Ejecución

El pipeline se puede ejecutar:
- **Automáticamente**: Después del deployment de infraestructura
- **Manualmente**: Para verificaciones on-demand
- **Programado**: Con triggers de tiempo

### Variables de Entorno Configurables

```groovy
// En el Jenkinsfile, puedes ajustar:
FRONTEND_PORT = "3000"          // Puerto del frontend
AUTH_API_PORT = "8000"          // Puerto de auth-api
TODOS_API_PORT = "8082"         // Puerto de todos-api
ZIPKIN_PORT = "9411"            // Puerto de Zipkin
HEALTH_CHECK_TIMEOUT = "60"     // Timeout para health checks
```

## 🔧 Troubleshooting

### Problemas Comunes

1. **Error "No se pudo obtener la IP de la VM"**
   - Verificar que el job de infraestructura ejecutó exitosamente
   - Confirmar que `droplet.properties` contiene `DROPLET_IP`

2. **Error de conectividad SSH**
   - Verificar credenciales de `deploy-password`
   - Confirmar que la VM está accesible desde Jenkins

3. **Tests fallan pero servicios funcionan**
   - Revisar logs específicos en `test-results/`
   - Verificar puertos y configuración de red de la VM

4. **Timeout en health checks**
   - Aumentar `HEALTH_CHECK_TIMEOUT`
   - Verificar que los servicios estén completamente iniciados

### Logs de Debug

En caso de fallo, el pipeline genera automáticamente:
- `emergency-logs/docker-compose.log`: Logs de todos los contenedores
- `emergency-logs/container-status.log`: Estado de contenedores
- `test-results/*-error.log`: Logs específicos de tests fallidos

## 🔗 Integración con Infraestructura

Este pipeline está diseñado para trabajar junto con el pipeline de infraestructura que:
1. Crea/verifica la VM en DigitalOcean
2. Despliega la aplicación con Docker Compose
3. Guarda la IP de la VM en `droplet.properties`

La secuencia completa sería:
```
Infraestructura Pipeline → Aplicación Desplegada → Integridad Pipeline
```

## 📈 Mejoras Futuras

- [ ] Integración con sistemas de alertas (Slack, email)
- [ ] Métricas históricas y trending
- [ ] Tests de carga y performance
- [ ] Integración con herramientas de APM
- [ ] Tests de seguridad automatizados