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

- Pruebas (Jest):

  - `todos-api/__mocks__/redis.js`: mock de Redis en memoria compatible con las llamadas usadas.
  - `todos-api/__tests__/cache-aside.test.js` verifica:
    - Primer `GET /todos` responde con `X-Cache: MISS` y populariza Redis.
    - Segundo `GET /todos` responde con `X-Cache: HIT`.
    - `POST /todos` invalida la clave; siguiente `GET` vuelve a ser `MISS`.
  - Configuración: `todos-api/jest.config.js` y script `npm test` en `todos-api/package.json`.

- CI (GitHub Actions):

  - En `build-todos-api` se ejecuta `npm test`.
  - Job paralelo `todos-cache-test` corre específicamente los tests de `todos-api` (Node 18, `npm ci`, `npm test`) para visibilidad junto a `integration`, `retry-test` y `breaker-test`.

- Cómo correr localmente:
  - `cd todos-api && npm install && npm test`

### Circuit Breaker (aplicado)

- **Servicio**: `auth-api`
- **Alcance**: protege llamadas HTTP salientes hacia `users-api`.
- **Implementación**:
  - `auth-api/circuitbreaker.go`: wrapper `breakerHTTPClient` basado en `github.com/sony/gobreaker`.
  - Cuenta como fallo cualquier respuesta `>= 500` (cierra el body) y errores de red; abre el circuito cuando se cumple el umbral.
  - Configurable por variables de entorno:
    - `CB_MAX_REQUESTS` (half-open), `CB_INTERVAL_SECONDS`, `CB_TIMEOUT_SECONDS`,
      `CB_MIN_REQUESTS`, `CB_FAILURE_RATIO`, `CB_CONSECUTIVE_FAILURES`.
  - Endpoints de estado en `auth-api/main.go`:
    - `GET /debug/breaker`, `GET /status/circuit-breaker`, `GET /health/circuit-breaker` devuelven `state` y contadores (`Counts` y `LocalCounts`).
  - Orden de encadenado: el cliente de **retry** envuelve al **breaker** (retry → breaker → cliente HTTP). Así, cada intento del retry es observado y contado por el breaker.
- **Pruebas unitarias**:
  - `auth-api/circuitbreaker_test.go`: el breaker abre tras varios fallos y vuelve a cerrar tras `Timeout` con un backend sano.
  - `auth-api/circuitbreaker_httpstatus_test.go`: confirma que `500` se contabiliza como fallo y abre el circuito.
- **Prueba manual de integración** (bash):
  - `scripts/cb-test.sh`: descubre el endpoint del breaker, detiene `users-api` para provocar fallos, verifica transición a `open`, luego arranca `users-api` y valida `half-open` → `closed`.
  - Uso: `bash scripts/cb-test.sh` (requiere Docker y el stack levantado por Compose).
- **Notas**:
  - El breaker corta fallos sistémicos; el retry gestiona fallos transitorios. Combinados, mejoran resiliencia y evitan tormentas contra dependencias caídas.
  - Los endpoints de estado facilitan observabilidad básica. Futuro: exportar métricas Prometheus si se necesita monitoreo avanzado.

Alternativas relacionadas: autoscaling (HPA/KEDA) o federated identity (OIDC con un IdP externo) según el alcance del taller.

### Retry con backoff (aplicado)

- **Servicio**: `auth-api`
- **Alcance**: llamadas HTTP salientes al `users-api` (GET `/users/<username>`)
- **Implementación**:
  - `auth-api/retry.go`: `retryHTTPClient` con `RetryConfig` aplicado solo a métodos idempotentes (GET/HEAD/OPTIONS).
  - Reintentos en errores de red, `5xx` y `429`; respeta `context.Context` (cancelación/timeout) y cierra el body antes de reintentar.
  - Backoff exponencial con jitter (por defecto: 3 intentos, base 200ms, máximo 2s).
  - Cableado en `auth-api/main.go`: el retry envuelve al cliente después del Circuit Breaker para mantener métricas del breaker.
- **Pruebas unitarias**:
  - `auth-api/retry_test.go` y `auth-api/retry_test_helpers.go` cubren:
    - Recuperación tras `500 -> 200` en GET
    - No reintentar en POST (no idempotente)
    - Reintento tras error de red y éxito posterior
- **Prueba determinista end-to-end** (bash):
  - `scripts/test-retry.sh` levanta `wiremock` y configura el escenario `UsersApiFlaky` para responder primero `500` y luego `200` a `/users/*`.
  - Valida que las dos últimas respuestas a `/users/*` sean el conjunto `{500,200}` (orden indiferente), que el breaker observe ≥ 2 intentos y reporta `elapsedMs`.
  - Integrado en CI (`.github/workflows/ci-integrations.yml`, job `retry-test`).
- **Compose override para la prueba**:
  - `docker-compose.retry.yml` añade `wiremock` y configura `USERS_API_ADDRESS` de `auth-api` apuntando a `wiremock`.
- **Cómo ejecutarlo**:
  - Local: `bash scripts/test-retry.sh`
  - CI: job `retry-test` se ejecuta automáticamente; instala `jq` y falla si no se cumple el comportamiento esperado.
- **Notas**:
  - No se reintentan operaciones no idempotentes (p. ej., POST).
  - El breaker mantiene contadores accesibles en `GET /status/circuit-breaker` para observabilidad básica.
  - Futuro: exponer métricas Prometheus del retry/breaker si se requiere monitoreo avanzado.
