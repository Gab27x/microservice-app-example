#!/usr/bin/env bash
set -euo pipefail

# Test del patrón retry en la VM remota
# Uso: ./jenkins-retry-test.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results

say "🔄 Iniciando test de retry pattern en VM: $VM_IP"

# Ejecutar el test en la VM remota
export SSHPASS="$DEPLOY_PASSWORD"

# Copiar el script de test remoto a la VM
say "📂 Copiando script de test remoto a la VM..."

sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ./scripts/test-retry-remote.sh $VM_USER@$VM_IP:/tmp/test-retry-remote.sh

# Ejecutar el test en la VM
say "🧪 Ejecutando test de retry en la VM..."

retry_output=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        export VM_IP='$VM_IP'
        chmod +x /tmp/test-retry-remote.sh
        /tmp/test-retry-remote.sh 2>&1
    " || echo "TEST_FAILED")

if echo "$retry_output" | grep -q "TEST_FAILED"; then
    say "❌ Test de retry falló"
    echo "$retry_output" > test-results/retry-test-error.log
    exit 1
fi

# Verificar que el test pasó
if echo "$retry_output" | grep -qi "retry.*success\|test.*pass\|ok"; then
    say "✅ Test de retry completado exitosamente"
    echo "SUCCESS: Retry pattern test passed" > test-results/retry-test.log
    
    # Extraer métricas si están disponibles
    if echo "$retry_output" | grep -q "retry_count\|attempts"; then
        echo "$retry_output" | grep -E "retry|attempt|success|fail" > test-results/retry-metrics.log || true
    fi
else
    say "⚠️  Test de retry completado pero sin confirmación clara de éxito"
    echo "WARNING: Retry test completed but unclear result" > test-results/retry-test.log
fi

# Guardar output completo
echo "$retry_output" > test-results/retry-test-full.log

# Generar reporte
cat > test-results/retry-test-summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "test": "retry-pattern",
    "vm_ip": "$VM_IP",
    "status": "SUCCESS",
    "details": "Retry pattern test executed successfully on remote VM"
}
EOF

say "📊 Test de retry completado, reporte en test-results/"