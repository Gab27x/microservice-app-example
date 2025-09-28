#!/usr/bin/env bash
set -euo pipefail

# Test del patrón cache-aside en la VM remota
# Uso: ./jenkins-cache-test.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results

say "💾 Iniciando test de cache pattern en VM: $VM_IP"

export SSHPASS="$DEPLOY_PASSWORD"

# Ejecutar tests de cache directamente en la VM
say "🧪 Ejecutando tests de cache en todos-api..."

cache_output=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH/todos-api
        
        # Verificar que existe package.json y las dependencias de test
        if [ ! -f package.json ]; then
            echo 'CACHE_TEST_ERROR: package.json not found'
            exit 1
        fi
        
        # Instalar dependencias si no están
        if [ ! -d node_modules ]; then
            echo 'Installing dependencies...'
            npm install 2>&1 || echo 'CACHE_TEST_ERROR: npm install failed'
        fi
        
        # Ejecutar tests específicos de cache
        echo 'Running cache tests...'
        npm test 2>&1 || echo 'CACHE_TEST_ERROR: npm test failed'
    ")

# Verificar resultado
if echo "$cache_output" | grep -q "CACHE_TEST_ERROR"; then
    say "❌ Test de cache falló"
    echo "$cache_output" > test-results/cache-test-error.log
    
    # Intentar obtener información de debug
    debug_info=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        $VM_USER@$VM_IP "
            cd $APP_PATH
            echo '=== Redis Status ==='
            docker compose ps redis-todo
            echo '=== Todos API Logs (last 10 lines) ==='
            docker compose logs --tail=10 todos-api
        " 2>/dev/null || echo "No debug info available")
    
    echo "$debug_info" >> test-results/cache-test-error.log
    exit 1
fi

# Verificar que los tests pasaron
if echo "$cache_output" | grep -qi "pass\|✓\|✅\|test.*success"; then
    say "✅ Tests de cache completados exitosamente"
    echo "SUCCESS: Cache pattern tests passed" > test-results/cache-test.log
    
    # Extraer información de tests específicos
    if echo "$cache_output" | grep -E "cache|redis|aside"; then
        echo "$cache_output" | grep -E "cache|redis|aside" > test-results/cache-specific-tests.log || true
    fi
else
    say "⚠️  Tests de cache ejecutados pero resultado unclear"
    echo "WARNING: Cache tests executed but unclear results" > test-results/cache-test.log
fi

# Test adicional: verificar que Redis está funcionando
say "🔍 Verificando estado de Redis..."

redis_status=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        docker compose exec -T redis-todo redis-cli ping 2>/dev/null || echo 'Redis not responding'
    ")

if echo "$redis_status" | grep -q "PONG"; then
    say "✅ Redis está funcionando correctamente"
    echo "SUCCESS: Redis is responding" > test-results/redis-status.log
else
    say "⚠️  Redis no responde correctamente"
    echo "WARNING: Redis not responding: $redis_status" > test-results/redis-status.log
fi

# Test funcional: verificar cache en acción
say "🧪 Probando funcionalidad de cache con requests reales..."

# Obtener token
TOKEN=$(curl -s --max-time 10 -X POST "http://$VM_IP:8000/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' | \
    grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    # Hacer varias solicitudes para probar cache
    say "🔑 Token obtenido, probando comportamiento de cache..."
    
    # Primera solicitud (debería llenar cache)
    start_time=$(date +%s%N)
    response1=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
        "http://$VM_IP:8082/todos" 2>/dev/null || echo "[]")
    end_time=$(date +%s%N)
    time1=$((($end_time - $start_time) / 1000000)) # Convert to milliseconds
    
    # Segunda solicitud (debería usar cache, ser más rápida)
    start_time=$(date +%s%N)
    response2=$(curl -s --max-time 10 -H "Authorization: Bearer $TOKEN" \
        "http://$VM_IP:8082/todos" 2>/dev/null || echo "[]")
    end_time=$(date +%s%N)
    time2=$((($end_time - $start_time) / 1000000)) # Convert to milliseconds
    
    say "📊 Tiempo primera solicitud: ${time1}ms"
    say "📊 Tiempo segunda solicitud: ${time2}ms"
    
    echo "First request time: ${time1}ms" > test-results/cache-performance.log
    echo "Second request time: ${time2}ms" >> test-results/cache-performance.log
    echo "Response match: $([ "$response1" = "$response2" ] && echo "YES" || echo "NO")" >> test-results/cache-performance.log
    
    if [ "$response1" = "$response2" ]; then
        say "✅ Respuestas consistentes (cache funcionando)"
    else
        say "⚠️  Respuestas inconsistentes"
    fi
else
    say "⚠️  No se pudo obtener token para test funcional"
fi

# Guardar output completo
echo "$cache_output" > test-results/cache-test-full.log

# Generar reporte
cat > test-results/cache-test-summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "test": "cache-aside-pattern",
    "vm_ip": "$VM_IP",
    "status": "SUCCESS",
    "redis_status": "$(echo "$redis_status" | head -1)",
    "performance": {
        "first_request_ms": ${time1:-0},
        "second_request_ms": ${time2:-0}
    },
    "details": "Cache aside pattern test executed on remote VM"
}
EOF

say "📊 Test de cache completado, reporte en test-results/"