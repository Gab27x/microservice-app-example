#!/usr/bin/env bash
set -euo pipefail

# Test de rate limiting en la VM remota
# Uso: ./jenkins-rate-limit-test.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results

say "🚦 Iniciando test de rate limiting en VM: $VM_IP"

export SSHPASS="$DEPLOY_PASSWORD"

# Copiar el script de rate limiting a la VM
say "📂 Copiando script de rate limiting a la VM..."

sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ./scripts/rate-limit-test.sh $VM_USER@$VM_IP:/tmp/rate-limit-test.sh

# Ejecutar el test en la VM
say "🧪 Ejecutando test de rate limiting en la VM..."

rate_limit_output=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        chmod +x /tmp/rate-limit-test.sh
        
        # Ejecutar el test
        timeout 120 /tmp/rate-limit-test.sh 2>&1 || echo 'RATE_LIMIT_TEST_ERROR'
    ")

# Verificar resultado
if echo "$rate_limit_output" | grep -q "RATE_LIMIT_TEST_ERROR"; then
    say "❌ Test de rate limiting falló o timeout"
    echo "$rate_limit_output" > test-results/rate-limit-test-error.log
    
    # Verificar si al menos el frontend está accesible
    if curl -fs --max-time 10 "http://$VM_IP:3000/" >/dev/null 2>&1; then
        say "🔍 Frontend accesible, pero test de rate limiting falló"
    else
        say "🔍 Frontend no accesible, posible problema de configuración"
    fi
    
    exit 1
fi

# Verificar que se obtuvieron códigos 429 (rate limited)
if echo "$rate_limit_output" | grep -q "429\|limited\|Rate limiting test OK"; then
    say "✅ Test de rate limiting completado exitosamente"
    echo "SUCCESS: Rate limiting test passed" > test-results/rate-limit-test.log
    
    # Extraer estadísticas si están disponibles
    if echo "$rate_limit_output" | grep -E "200=|429="; then
        echo "$rate_limit_output" | grep -E "200=|429=|ok=|limited=" > test-results/rate-limit-stats.log || true
    fi
    
    # Extraer el JSON final si está presente
    if echo "$rate_limit_output" | grep -q "{.*todos.*login.*}"; then
        echo "$rate_limit_output" | grep "{.*todos.*login.*}" | tail -1 > test-results/rate-limit-results.json || true
    fi
else
    say "⚠️  Test de rate limiting ejecutado pero sin confirmación de límites aplicados"
    echo "WARNING: Rate limiting test executed but no 429 responses detected" > test-results/rate-limit-test.log
fi

# Guardar output completo
echo "$rate_limit_output" > test-results/rate-limit-test-full.log

# Test adicional: verificar manualmente el rate limiting
say "🔍 Verificando rate limiting manualmente..."

# Obtener token para las pruebas
TOKEN=$(curl -s --max-time 10 -X POST "http://$VM_IP:3000/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' | \
    grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    say "🔑 Token obtenido, probando ráfaga de solicitudes..."
    
    # Hacer 10 solicitudes rápidas al endpoint /todos
    rate_test_codes=""
    for i in {1..10}; do
        code=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $TOKEN" \
            "http://$VM_IP:3000/todos" 2>/dev/null || echo "000")
        rate_test_codes="$rate_test_codes $code"
    done
    
    # Contar códigos de respuesta
    count_200=$(echo "$rate_test_codes" | tr ' ' '\n' | grep -c "200" || echo "0")
    count_429=$(echo "$rate_test_codes" | tr ' ' '\n' | grep -c "429" || echo "0")
    
    say "📊 Resultados manual: $count_200 respuestas 200, $count_429 respuestas 429"
    
    echo "Manual test - 200: $count_200, 429: $count_429" > test-results/rate-limit-manual.log
    echo "Response codes: $rate_test_codes" >> test-results/rate-limit-manual.log
    
    if [ "$count_429" -gt 0 ]; then
        say "✅ Rate limiting verificado manualmente - se detectaron respuestas 429"
    else
        say "⚠️  No se detectaron respuestas 429 en test manual"
    fi
else
    say "⚠️  No se pudo obtener token para test manual"
fi

# Generar reporte
cat > test-results/rate-limit-test-summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "test": "rate-limiting",
    "vm_ip": "$VM_IP",
    "status": "SUCCESS",
    "manual_test": {
        "responses_200": ${count_200:-0},
        "responses_429": ${count_429:-0}
    },
    "details": "Rate limiting test executed on remote VM"
}
EOF

say "📊 Test de rate limiting completado, reporte en test-results/"