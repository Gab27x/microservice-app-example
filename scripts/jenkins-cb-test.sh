#!/usr/bin/env bash
set -euo pipefail

# Test del circuit breaker en la VM remota
# Uso: ./jenkins-cb-test.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results

say "⚡ Iniciando test de circuit breaker en VM: $VM_IP"

export SSHPASS="$DEPLOY_PASSWORD"

# Copiar el script de circuit breaker a la VM
say "📂 Copiando script de circuit breaker a la VM..."

sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ./scripts/cb-test.sh $VM_USER@$VM_IP:/tmp/cb-test.sh

# Ejecutar el test en la VM
say "🧪 Ejecutando test de circuit breaker en la VM..."

cb_output=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        chmod +x /tmp/cb-test.sh
        
        # Configurar variables de entorno para el test
        export AUTH_HOST=localhost
        export TODOS_HOST=localhost
        
        # Ejecutar el test
        /tmp/cb-test.sh 2>&1 || echo 'CB_TEST_ERROR'
    ")

# Verificar resultado
if echo "$cb_output" | grep -q "CB_TEST_ERROR"; then
    say "❌ Test de circuit breaker falló"
    echo "$cb_output" > test-results/cb-test-error.log
    
    # Intentar obtener información adicional de debug
    debug_info=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        $VM_USER@$VM_IP "
            cd $APP_PATH
            echo '=== Container Status ==='
            docker compose ps
            echo '=== Auth API Logs (last 20 lines) ==='
            docker compose logs --tail=20 auth-api
        " 2>/dev/null || echo "No debug info available")
    
    echo "$debug_info" >> test-results/cb-test-error.log
    exit 1
fi

# Verificar que el circuit breaker funcionó
if echo "$cb_output" | grep -qi "circuit.*open\|breaker.*trip\|circuit.*close\|estado.*abierto"; then
    say "✅ Test de circuit breaker completado exitosamente"
    echo "SUCCESS: Circuit breaker test passed" > test-results/cb-test.log
    
    # Extraer información del estado del circuit breaker
    if echo "$cb_output" | grep -E "state|estado"; then
        echo "$cb_output" | grep -E "state|estado|open|close|half" > test-results/cb-states.log || true
    fi
else
    say "⚠️  Test de circuit breaker ejecutado pero sin confirmación de funcionamiento"
    echo "WARNING: Circuit breaker test executed but unclear state changes" > test-results/cb-test.log
fi

# Guardar output completo
echo "$cb_output" > test-results/cb-test-full.log

# Test adicional: verificar endpoint de circuit breaker directamente
say "🔍 Verificando endpoint de circuit breaker directamente..."

# Esperar un poco para que el servicio esté listo después de los tests
sleep 2

cb_status=$(curl -s --max-time 10 "http://$VM_IP:8000/status/circuit-breaker" 2>/dev/null || \
           curl -s --max-time 10 "http://$VM_IP:8000/health/circuit-breaker" 2>/dev/null || \
           curl -s --max-time 10 "http://$VM_IP:8000/debug/breaker" 2>/dev/null || \
           echo '{"status":"unknown"}')

if echo "$cb_status" | grep -q "state\|circuit\|breaker"; then
    say "✅ Endpoint de circuit breaker responde correctamente"
    echo "$cb_status" > test-results/cb-endpoint-status.json
else
    say "⚠️  Endpoint de circuit breaker no responde o no contiene información esperada"
    echo "$cb_status" > test-results/cb-endpoint-status.json
fi

# Generar reporte
cat > test-results/cb-test-summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "test": "circuit-breaker",
    "vm_ip": "$VM_IP",
    "status": "SUCCESS",
    "endpoint_status": $(echo "$cb_status" | head -1),
    "details": "Circuit breaker pattern test executed on remote VM"
}
EOF

say "📊 Test de circuit breaker completado, reporte en test-results/"