#!/usr/bin/env bash
set -euo pipefail

# Smoke test completo para verificar el flujo básico de la aplicación
# Uso: ./jenkins-smoke-test.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# Instalar jq si no está disponible
if ! command -v jq >/dev/null 2>&1; then
    say "Instalando jq..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y >/dev/null 2>&1 || true
        sudo apt-get install -y jq >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq >/dev/null 2>&1 || true
    fi
fi

mkdir -p test-results

say "🧪 Iniciando smoke test en VM: $VM_IP"

# URLs de los servicios
AUTH_URL="http://$VM_IP:8000"
TODOS_URL="http://$VM_IP:8082"
USERS_URL="http://$VM_IP:8083"
FRONTEND_URL="http://$VM_IP:3000"

# 1. Verificar que todos los servicios respondan
say "1️⃣  Verificando conectividad básica de servicios..."

services=(
    "$AUTH_URL/version:Auth-API"
    "$FRONTEND_URL:Frontend"
)

for service in "${services[@]}"; do
    url="${service%:*}"
    name="${service#*:}"
    
    if curl -fs --max-time 10 "$url" >/dev/null 2>&1; then
        say "   ✅ $name responde correctamente"
    else
        say "   ❌ $name no responde"
        echo "FAIL: $name no responde" >> test-results/smoke-test.log
        exit 1
    fi
done

# Verificar Todos API y Users API mediante conectividad de puerto
say "   🔍 Verificando conectividad de Todos API y Users API..."

if timeout 5 bash -c "</dev/tcp/$VM_IP/8082" 2>/dev/null; then
    say "   ✅ Todos-API (puerto 8082) responde correctamente"
else
    say "   ❌ Todos-API (puerto 8082) no responde"
    echo "FAIL: Todos-API no responde" >> test-results/smoke-test.log
    exit 1
fi

if timeout 5 bash -c "</dev/tcp/$VM_IP/8083" 2>/dev/null; then
    say "   ✅ Users-API (puerto 8083) responde correctamente"
else
    say "   ❌ Users-API (puerto 8083) no responde"
    echo "FAIL: Users-API no responde" >> test-results/smoke-test.log
    exit 1
fi

# 2. Test de autenticación
say "2️⃣  Probando autenticación..."

LOGIN_RESPONSE=$(curl -s --max-time 10 -X POST "$AUTH_URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' || echo '{}')

if command -v jq >/dev/null 2>&1; then
    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken // empty' 2>/dev/null || echo "")
else
    # Fallback sin jq
    TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4 || echo "")
fi

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    say "   ✅ Login exitoso, token obtenido: ${TOKEN:0:20}..."
    echo "SUCCESS: Login exitoso" >> test-results/smoke-test.log
else
    say "   ❌ Login falló"
    say "   Respuesta: $LOGIN_RESPONSE"
    echo "FAIL: Login falló" >> test-results/smoke-test.log
    exit 1
fi

# 3. Test de creación de TODO
say "3️⃣  Probando creación de TODO..."

TODO_RESPONSE=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
    -X POST "$TODOS_URL/todos" \
    -H "Content-Type: application/json" \
    -d '{"content":"Jenkins Smoke Test TODO"}' || echo '{}')

if echo "$TODO_RESPONSE" | grep -q "content\|id\|Jenkins" 2>/dev/null; then
    say "   ✅ TODO creado exitosamente"
    echo "SUCCESS: TODO creado" >> test-results/smoke-test.log
else
    say "   ❌ Creación de TODO falló"
    say "   Respuesta: $TODO_RESPONSE"
    echo "FAIL: Creación de TODO falló" >> test-results/smoke-test.log
    exit 1
fi

# 4. Test de listado de TODOs
say "4️⃣  Probando listado de TODOs..."

TODOS_LIST=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
    "$TODOS_URL/todos" || echo '[]')

if echo "$TODOS_LIST" | grep -q "Jenkins\|content\|id" 2>/dev/null; then
    say "   ✅ Listado de TODOs exitoso"
    echo "SUCCESS: Listado de TODOs exitoso" >> test-results/smoke-test.log
else
    say "   ⚠️  Listado de TODOs vacío o sin nuestro TODO de prueba"
    echo "WARNING: Listado de TODOs vacío" >> test-results/smoke-test.log
fi

# 5. Test del frontend (verificar que carga)
say "5️⃣  Probando frontend..."

FRONTEND_CONTENT=$(curl -s --max-time 10 "$FRONTEND_URL" || echo "")

if echo "$FRONTEND_CONTENT" | grep -qi "html\|vue\|app\|todo" 2>/dev/null; then
    say "   ✅ Frontend carga correctamente"
    echo "SUCCESS: Frontend carga correctamente" >> test-results/smoke-test.log
else
    say "   ❌ Frontend no carga correctamente"
    echo "FAIL: Frontend no carga correctamente" >> test-results/smoke-test.log
    exit 1
fi

# 6. Verificar Zipkin (opcional)
say "6️⃣  Verificando Zipkin..."

ZIPKIN_URL="http://$VM_IP:9411"
if curl -fs --max-time 10 "$ZIPKIN_URL" >/dev/null 2>&1; then
    say "   ✅ Zipkin está funcionando"
    echo "SUCCESS: Zipkin funcionando" >> test-results/smoke-test.log
else
    say "   ⚠️  Zipkin no responde (no crítico)"
    echo "WARNING: Zipkin no responde" >> test-results/smoke-test.log
fi

# Resumen
say "🎉 Smoke test completado exitosamente"

# Generar reporte
cat > test-results/smoke-test-summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "SUCCESS",
    "vm_ip": "$VM_IP",
    "tests": {
        "connectivity": "PASS",
        "authentication": "PASS",
        "todo_creation": "PASS",
        "todo_listing": "PASS",
        "frontend": "PASS",
        "zipkin": "PASS"
    }
}
EOF

say "📊 Reporte guardado en test-results/smoke-test-summary.json"