#!/usr/bin/env bash
set -euo pipefail

# Reporte final del estado de la aplicación en la VM
# Uso: ./jenkins-final-report.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results

say "📊 Generando reporte final de integridad en VM: $VM_IP"

export SSHPASS="$DEPLOY_PASSWORD"

# Verificar que existen los reportes de tests anteriores
test_files=(
    "test-results/smoke-test-summary.json"
    "test-results/retry-test-summary.json"
    "test-results/cb-test-summary.json"
    "test-results/rate-limit-test-summary.json"
    "test-results/cache-test-summary.json"
    "test-results/application-health.json"
)

tests_executed=0
tests_passed=0

# Recopilar resultados de todos los tests
for test_file in "${test_files[@]}"; do
    if [ -f "$test_file" ]; then
        tests_executed=$((tests_executed + 1))
        
        if grep -q '"status": "SUCCESS"' "$test_file" 2>/dev/null || 
           grep -q '"overall_status": "HEALTHY"' "$test_file" 2>/dev/null; then
            tests_passed=$((tests_passed + 1))
        fi
    fi
done

# Obtener información final del sistema
say "🔍 Recopilando información final del sistema..."

final_system_info=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        
        echo '=== Final Container Status ==='
        docker compose ps --format 'table {{.Name}}\t{{.State}}\t{{.Status}}'
        
        echo ''
        echo '=== Resource Usage Summary ==='
        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | head -10
        
        echo ''
        echo '=== Network Status ==='
        docker network ls | grep -E 'microservice|bridge'
        
        echo ''
        echo '=== Volume Status ==='
        docker volume ls | grep -E 'microservice|todo|redis' || echo 'No specific volumes found'
        
        echo ''
        echo '=== System Uptime ==='
        uptime
        
        echo ''
        echo '=== Disk Space ==='
        df -h /opt/microservice-app | tail -1
    " 2>/dev/null || echo "Could not gather final system info")

echo "$final_system_info" > test-results/final-system-info.log

# Hacer un último health check de todos los endpoints
say "🩺 Health check final de endpoints..."

endpoints=(
    "http://$VM_IP:3000:Frontend"
    "http://$VM_IP:8000/version:Auth-API"
    "http://$VM_IP:8082/health:Todos-API"
    "http://$VM_IP:9411:Zipkin"
)

endpoint_results=""
healthy_endpoints=0
total_endpoints=${#endpoints[@]}

for endpoint in "${endpoints[@]}"; do
    url="${endpoint%:*}"
    name="${endpoint#*:}"
    
    if curl -fs --max-time 10 "$url" >/dev/null 2>&1; then
        endpoint_results="$endpoint_results\n    ✅ $name: OK"
        healthy_endpoints=$((healthy_endpoints + 1))
    else
        endpoint_results="$endpoint_results\n    ❌ $name: FAIL"
    fi
done

# Calcular scores
endpoint_score=$((healthy_endpoints * 100 / total_endpoints))
test_score=$((tests_passed * 100 / tests_executed))
overall_score=$(((endpoint_score + test_score) / 2))

# Determinar estado general
if [ $overall_score -ge 90 ]; then
    overall_status="EXCELLENT"
    status_emoji="🟢"
elif [ $overall_score -ge 75 ]; then
    overall_status="GOOD"
    status_emoji="🟡"
elif [ $overall_score -ge 50 ]; then
    overall_status="DEGRADED"
    status_emoji="🟠"
else
    overall_status="CRITICAL"
    status_emoji="🔴"
fi

# Generar reporte final detallado
cat > test-results/final-integrity-report.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "vm_ip": "$VM_IP",
    "test_execution": {
        "total_tests": $tests_executed,
        "passed_tests": $tests_passed,
        "success_rate": "${test_score}%"
    },
    "endpoint_health": {
        "healthy_endpoints": $healthy_endpoints,
        "total_endpoints": $total_endpoints,
        "availability": "${endpoint_score}%"
    },
    "overall": {
        "score": $overall_score,
        "status": "$overall_status",
        "recommendation": "$([ $overall_score -ge 90 ] && echo "System is performing excellently" || 
                           [ $overall_score -ge 75 ] && echo "System is healthy with minor issues" ||
                           [ $overall_score -ge 50 ] && echo "System has significant issues requiring attention" ||
                           echo "System is in critical state requiring immediate action")"
    },
    "details": {
        "smoke_test": "$([ -f test-results/smoke-test-summary.json ] && echo "EXECUTED" || echo "SKIPPED")",
        "retry_pattern": "$([ -f test-results/retry-test-summary.json ] && echo "EXECUTED" || echo "SKIPPED")",
        "circuit_breaker": "$([ -f test-results/cb-test-summary.json ] && echo "EXECUTED" || echo "SKIPPED")",
        "rate_limiting": "$([ -f test-results/rate-limit-test-summary.json ] && echo "EXECUTED" || echo "SKIPPED")",
        "cache_pattern": "$([ -f test-results/cache-test-summary.json ] && echo "EXECUTED" || echo "SKIPPED")",
        "log_analysis": "$([ -f test-results/application-health.json ] && echo "EXECUTED" || echo "SKIPPED")"
    }
}
EOF

# Generar reporte en markdown para mejor legibilidad
cat > test-results/FINAL-REPORT.md << EOF
# 📋 Reporte Final de Integridad de Microservicios

**Fecha:** $(date)  
**VM:** $VM_IP  
**Estado General:** $status_emoji $overall_status ($overall_score%)  

## 🎯 Resumen Ejecutivo

La verificación de integridad de los microservicios ha sido completada con los siguientes resultados:

- **Tests Ejecutados:** $tests_passed/$tests_executed pasaron (${test_score}%)
- **Endpoints Saludables:** $healthy_endpoints/$total_endpoints disponibles (${endpoint_score}%)
- **Score General:** $overall_score/100

## 📊 Resultados por Categoría

### ✅ Tests de Integridad
$([ -f test-results/smoke-test-summary.json ] && echo "- **Smoke Test:** ✅ EJECUTADO" || echo "- **Smoke Test:** ❌ NO EJECUTADO")
$([ -f test-results/retry-test-summary.json ] && echo "- **Retry Pattern:** ✅ EJECUTADO" || echo "- **Retry Pattern:** ❌ NO EJECUTADO")
$([ -f test-results/cb-test-summary.json ] && echo "- **Circuit Breaker:** ✅ EJECUTADO" || echo "- **Circuit Breaker:** ❌ NO EJECUTADO")
$([ -f test-results/rate-limit-test-summary.json ] && echo "- **Rate Limiting:** ✅ EJECUTADO" || echo "- **Rate Limiting:** ❌ NO EJECUTADO")
$([ -f test-results/cache-test-summary.json ] && echo "- **Cache Pattern:** ✅ EJECUTADO" || echo "- **Cache Pattern:** ❌ NO EJECUTADO")

### 🌐 Estado de Endpoints
$endpoint_results

### 📈 Recomendaciones

$([ $overall_score -ge 90 ] && echo "🎉 **Excelente:** El sistema está funcionando óptimamente. Mantener monitoreo regular." ||
  [ $overall_score -ge 75 ] && echo "👍 **Bueno:** El sistema está saludable con problemas menores. Revisar logs para optimizaciones." ||
  [ $overall_score -ge 50 ] && echo "⚠️ **Degradado:** El sistema tiene problemas significativos. Revisar servicios fallidos y logs de error." ||
  echo "🚨 **Crítico:** El sistema está en estado crítico. Requiere atención inmediata de DevOps.")

## 📂 Archivos de Reporte

Los siguientes archivos contienen información detallada:

- \`final-integrity-report.json\` - Reporte completo en JSON
- \`application-health.json\` - Estado de salud de la aplicación
- \`final-system-info.log\` - Información final del sistema
- \`logs/\` - Directorio con logs de todos los servicios

---
*Generado automáticamente por Jenkins CI/CD Pipeline*
EOF

# Mostrar resumen en consola
say ""
say "==================== REPORTE FINAL ===================="
say "$status_emoji Estado General: $overall_status ($overall_score%)"
say "🧪 Tests: $tests_passed/$tests_executed pasaron (${test_score}%)"
say "🌐 Endpoints: $healthy_endpoints/$total_endpoints saludables (${endpoint_score}%)"
say ""

if [ $overall_score -ge 75 ]; then
    say "✅ La aplicación está funcionando correctamente"
    exit 0
elif [ $overall_score -ge 50 ]; then
    say "⚠️  La aplicación tiene algunos problemas pero está funcional"
    exit 0
else
    say "❌ La aplicación tiene problemas críticos"
    exit 1
fi