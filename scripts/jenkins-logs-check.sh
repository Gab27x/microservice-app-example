#!/usr/bin/env bash
set -euo pipefail

# Verificación de logs y trazas en la VM remota
# Uso: ./jenkins-logs-check.sh <VM_IP>

VM_IP="$1"

say() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

mkdir -p test-results logs

say "📋 Iniciando verificación de logs y trazas en VM: $VM_IP"

export SSHPASS="$DEPLOY_PASSWORD"

# 1. Obtener estado de todos los contenedores
say "🐳 Obteniendo estado de contenedores..."

container_status=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        docker compose ps --format 'table {{.Name}}\t{{.State}}\t{{.Status}}'
    " 2>/dev/null || echo "Error obteniendo estado de contenedores")

echo "$container_status" > test-results/container-status.log

# Verificar que todos los contenedores están corriendo
if echo "$container_status" | grep -v "Up\|running" | grep -q "Exit\|Down"; then
    say "❌ Algunos contenedores no están corriendo"
    echo "FAIL: Some containers are not running" > test-results/container-health.log
else
    say "✅ Todos los contenedores están corriendo"
    echo "SUCCESS: All containers are running" > test-results/container-health.log
fi

# 2. Obtener logs de cada servicio (últimas 50 líneas)
services=("auth-api" "todos-api" "users-api" "frontend" "log-message-processor" "zipkin" "redis-todo")

say "📄 Obteniendo logs de servicios..."

for service in "${services[@]}"; do
    say "   📑 Obteniendo logs de $service..."
    
    service_logs=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        $VM_USER@$VM_IP "
            cd $APP_PATH
            docker compose logs --tail=50 $service 2>/dev/null || echo 'Service $service not found or no logs'
        ")
    
    echo "$service_logs" > "logs/${service}.log"
    
    # Verificar logs por errores críticos
    if echo "$service_logs" | grep -qi "error\|exception\|fatal\|panic"; then
        error_count=$(echo "$service_logs" | grep -ci "error\|exception\|fatal\|panic")
        say "   ⚠️  $service tiene $error_count errores en logs"
        echo "$service: $error_count errors found" >> test-results/service-errors.log
        
        # Extraer errores específicos
        echo "$service_logs" | grep -i "error\|exception\|fatal\|panic" > "logs/${service}-errors.log" || true
    else
        say "   ✅ $service sin errores críticos en logs"
    fi
done

# 3. Verificar log-message-processor específicamente
say "📨 Verificando log-message-processor..."

processor_logs=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        docker compose logs --tail=100 log-message-processor 2>/dev/null || echo 'log-message-processor not found'
    ")

if echo "$processor_logs" | grep -q "Waiting for messages\|Processing message\|Connected to"; then
    say "✅ Log-message-processor está funcionando correctamente"
    echo "SUCCESS: Log message processor is working" > test-results/log-processor-status.log
else
    say "⚠️  Log-message-processor puede no estar funcionando correctamente"
    echo "WARNING: Log message processor status unclear" > test-results/log-processor-status.log
fi

# 4. Verificar trazas en Zipkin
say "🔍 Verificando trazas en Zipkin..."

# Primero verificar que Zipkin responda (acepta 200 y 302)
zipkin_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$VM_IP:9411" 2>/dev/null || echo "000")

if [ "$zipkin_status" = "200" ] || [ "$zipkin_status" = "302" ]; then
    say "✅ Zipkin está accesible (HTTP $zipkin_status)"
    
    # Intentar obtener servicios a través de API
    zipkin_traces=$(curl -s --max-time 10 "http://$VM_IP:9411/api/v2/services" 2>/dev/null || echo "[]")
    
    if echo "$zipkin_traces" | grep -q "auth-api\|todos-api\|users-api"; then
        say "✅ Zipkin está recibiendo trazas de los servicios"
        echo "SUCCESS: Zipkin is receiving traces" > test-results/zipkin-traces.log
        echo "$zipkin_traces" > test-results/zipkin-services.json
    else
        say "⚠️  Zipkin accesible pero sin trazas (puede ser normal en tests)"
        echo "INFO: Zipkin accessible but no traces yet" > test-results/zipkin-traces.log
    fi
else
    say "❌ Zipkin no está accesible (HTTP $zipkin_status)"
    echo "ERROR: Zipkin not accessible (HTTP $zipkin_status)" > test-results/zipkin-traces.log
fi

# 5. Verificar métricas de uso de recursos
say "📈 Obteniendo métricas de recursos..."

resource_usage=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        echo '=== CPU and Memory Usage ==='
        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' || true
        echo ''
        echo '=== Disk Usage ==='
        df -h /opt/microservice-app || true
    " 2>/dev/null || echo "Could not get resource usage")

echo "$resource_usage" > test-results/resource-usage.log

# 6. Verificar conectividad entre servicios (interno)
say "🔗 Verificando conectividad interna entre servicios..."

internal_connectivity=$(sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@$VM_IP "
        cd $APP_PATH
        echo 'Testing internal connectivity...'
        
        # Test auth-api -> users-api
        docker compose exec -T auth-api sh -c 'wget -q --spider http://users-api:8081/users/1 2>/dev/null && echo \"auth->users: OK\" || echo \"auth->users: FAIL\"' 2>/dev/null || echo 'auth->users: SKIP'
        
        # Test todos-api -> redis
        docker compose exec -T todos-api sh -c 'nc -z redis-todo 6379 2>/dev/null && echo \"todos->redis: OK\" || echo \"todos->redis: FAIL\"' 2>/dev/null || echo 'todos->redis: SKIP'
        
        # Test general network
        docker network ls | grep microservice || echo 'No custom network found'
    " 2>/dev/null || echo "Could not test internal connectivity")

echo "$internal_connectivity" > test-results/internal-connectivity.log

if echo "$internal_connectivity" | grep -q "OK"; then
    say "✅ Conectividad interna entre servicios está funcionando"
    echo "SUCCESS: Internal connectivity working" > test-results/connectivity-status.log
else
    say "⚠️  Problemas de conectividad interna o tests no ejecutables"
    echo "WARNING: Internal connectivity issues or tests not executable" > test-results/connectivity-status.log
fi

# 7. Resumen de health de la aplicación
say "🏥 Generando resumen de salud de la aplicación..."

# Contar servicios corriendo
running_services=$(echo "$container_status" | grep -c "Up\|running" || echo "0")
total_services=$(echo "$container_status" | grep -c "microservice\|redis\|zipkin" || echo "0")

# Contar errores encontrados
total_errors=$([ -f test-results/service-errors.log ] && wc -l < test-results/service-errors.log || echo "0")

# Generar reporte de salud
cat > test-results/application-health.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "vm_ip": "$VM_IP",
    "containers": {
        "running": $running_services,
        "total": $total_services,
        "status": "$([ "$running_services" -eq "$total_services" ] && echo "HEALTHY" || echo "DEGRADED")"
    },
    "logs": {
        "errors_found": $total_errors,
        "status": "$([ "$total_errors" -eq 0 ] && echo "CLEAN" || echo "ERRORS_PRESENT")"
    },
    "tracing": {
        "zipkin_accessible": $(curl -fs --max-time 5 "http://$VM_IP:9411" >/dev/null 2>&1 && echo "true" || echo "false"),
        "services_traced": $(echo "${zipkin_traces:-[]}" | grep -o "auth-api\|todos-api\|users-api" | wc -l || echo "0")
    },
    "overall_status": "$([ "$running_services" -eq "$total_services" ] && [ "$total_errors" -eq 0 ] && echo "HEALTHY" || echo "DEGRADED")"
}
EOF

overall_status=$([ "$running_services" -eq "$total_services" ] && [ "$total_errors" -eq 0 ] && echo "HEALTHY" || echo "DEGRADED")

if [ "$overall_status" = "HEALTHY" ]; then
    say "✅ Estado general de la aplicación: SALUDABLE"
else
    say "⚠️  Estado general de la aplicación: DEGRADADO"
fi

say "📊 Verificación de logs completada, reportes en test-results/ y logs/"