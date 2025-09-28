## Estrategias de Branching y Metodología

### Contexto general

- `main`: rama estable; solo contiene versiones productivas (taggeadas `vX.Y.Z`).

---

### 1) 2.5% Estrategia de branching para desarrolladores

**Enfoque:** Git Flow simplificado

**Por qué:**

- Permite manejar releases y hotfixes de forma eficiente.
- Es familiar y fácil de adoptar por equipos ágiles.
- Se integra bien con PRs, CI y versionado semántico.

**Metodología ágil propuesta: Kanban**

- Visualiza el flujo, limita trabajo en curso (WIP) y favorece mejora continua.
- Flexible y adaptable para requisitos cambiantes; menos ceremonias que Scrum.
- Gestión dinámica de prioridades, foco en entrega continua de valor.

**Ramas principales**

- `main`: estable, solo producción.
- `develop`: integración de nuevas features; debe estar siempre desplegable.

**Ramas de soporte**

- `feature/*`: una rama por funcionalidad (p. ej., `feature/login-jwt`, `feature/ui-todos`).
- `release/*`: preparación para producción (p. ej., `release/v1.0.0`).
- `hotfix/*`: correcciones urgentes sobre `main`.

**Flujo típico**

1. Crear `feature/*` desde `develop`.
2. Realizar PR a `develop` (revisiones, tests verdes, estándares de calidad).
3. Al cerrar un incremento, crear `release/*` desde `develop` para estabilización.
4. Merge `release/*` → `main` y generar tag `vX.Y.Z`; back-merge a `develop` si aplica.
5. Para bugs críticos en producción: crear `hotfix/*` desde `main`, luego merge a `main` (con tag) y back-merge a `develop`.

**Políticas recomendadas**

- Sin commits directos a `main` ni `develop`; todo vía PR.
- Convenciones de nombre: `feature/<scope-descriptivo>`, `release/v<semver>`, `hotfix/<ticket>`.
- Checks obligatorios en PR: build, tests, lint y revisión por al menos 1 par.

---

### 2) 2.5% Estrategia de branching para operaciones

**Enfoque:** GitOps ligero con Jenkins

**Ramas de infraestructura**

- `infra/main`: infraestructura productiva (pipelines de Jenkins, scripts de despliegue con Docker, etc.).
- `infra/dev`: pruebas y cambios de infraestructura (nuevos jobs, ajustes de pipelines, Dockerfiles, manifests, etc.).
- `infra/feature/*`: cambios incrementales específicos (p. ej., `infra/feature/jenkins-pipeline`).

**Flujo típico**

1. Probar cambios en `infra/feature/*`.
2. Merge a `infra/dev`: Jenkins ejecuta pruebas/validaciones de pipelines e infraestructura.
3. Una vez validados, merge a `infra/main`: Jenkins aplica/actualiza la infraestructura productiva.

**Ventajas de separar app e infraestructura**

- Desarrolladores iteran el código sin bloquear cambios de ops.
- Operaciones controlan scripts/pipelines sin afectar producción hasta estar validados.
- Jenkins dispara pipelines distintos según rama:
  - Código de app: `develop → staging`, `main → prod`.
  - Infraestructura: `infra/dev → entorno de pruebas`, `infra/main → prod`.

**Buenas prácticas**

- Versionar jobs/pipelines como código (Jenkinsfile) por servicio.
- Mantener scripts idempotentes y parametrizados por entorno.
- Artefactos versionados y promoción entre entornos (no rebuild).
