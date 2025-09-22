## Patrones de diseño de nube

### Cache-aside (aplicado)

- Servicio: `todos-api`
- Caché: Redis (`redis-todo` en `docker-compose.yml`)
- Clave: `todos:<username>`
- Lectura (GET `/todos`):
  - Se intenta `GET` en Redis. Si hay HIT, se responde y se marca encabezado `X-Cache: HIT`.
  - Si hay MISS, se carga del origen (memoria local del servicio), se responde y se hace `SETEX` con TTL `CACHE_TTL_SECONDS`.
- Escrituras (POST/DELETE):
  - Se actualiza el origen y se invalida la clave con `DEL` para mantener coherencia.
- Configuración: variable `CACHE_TTL_SECONDS` (por defecto 60) añadida en `docker-compose.yml`.

Beneficios: reducción de latencia en lecturas, menor carga en el origen. Riesgos: datos eventualmente desactualizados hasta la expiración; se mitiga con invalidación en mutaciones.

### Circuit Breaker (propuesto)

- Objetivo: proteger `todos-api` o `frontend` de latencias/fallas de `auth-api` o Redis.
- Implementación sugerida:
  - En `todos-api`, envolver llamadas a Redis con un breaker (p. ej., librería `opossum`) y fallback a respuesta sin cabecera `X-Cache` cuando el breaker esté abierto.
  - En `frontend`, para llamadas a `todos-api`, usar retry exponencial y breaker a nivel de fetch/Axios.
- Métricas: tasa de error, tiempo medio de respuesta, half-open test requests.

Alternativas de segundo patrón: autoscaling (HPA/KEDA) o federated identity (OIDC con un IdP externo) según el alcance del taller.
