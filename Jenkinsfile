pipeline {
    agent any
    
    options { 
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 45, unit: 'MINUTES')
    }
    
    triggers {
        // Trigger automático cuando el job de infraestructura termine exitosamente
        upstream(upstreamProjects: 'infra-microservice-app-example/infra/main', threshold: hudson.model.Result.SUCCESS)
    }
    
    parameters {
        string(
            name: 'VM_IP',
            defaultValue: '',
            description: 'IP de la VM donde están desplegados los microservicios (opcional si se obtiene automáticamente)'
        )
        choice(
            name: 'TEST_LEVEL',
            choices: ['FULL', 'SMOKE_ONLY', 'PATTERNS_ONLY'],
            description: 'Nivel de tests a ejecutar'
        )
    }
    
    environment {
        // Credenciales para conectar a la VM
        VM_USER = "deploy"
        APP_PATH = "/opt/microservice-app"
        
        // URLs se configurarán dinámicamente con la IP obtenida
        
        // Timeouts y configuración
        HEALTH_CHECK_TIMEOUT = "60"
        RETRY_ATTEMPTS = "3"
        
        // URLs de prueba (se actualizarán con la IP de la VM)
        FRONTEND_PORT = "3000"
        AUTH_API_PORT = "8000"
        TODOS_API_PORT = "8082"
        ZIPKIN_PORT = "9411"
    }
    
    stages {
        stage("Verificar Branch") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                echo "✅ Ejecutando tests de integridad en branch: ${env.BRANCH_NAME}"
                echo "📋 Pipeline de verificación iniciado para producción"
            }
        }
        
        stage("Obtener IP de VM") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                script {
                    def ipObtained = false
                    
                    // Prioridad 1: IP desde parámetro manual
                    if (params.VM_IP && params.VM_IP.trim() != '') {
                        env.VM_IP = params.VM_IP.trim()
                        echo "✅ VM IP obtenida desde parámetro: ${env.VM_IP}"
                        ipObtained = true
                    }
                    
                    // Prioridad 2: Obtener IP desde variables de entorno del job upstream
                    if (!ipObtained) {
                        try {
                            echo "🔍 Intentando obtener IP desde variables de entorno del job upstream..."
                            
                            // Método 1: Copiar artefactos usando Jenkins API interna
                            def upstreamJob = Jenkins.instance.getItem("infra-microservice-app-example").getItem("infra%2Fmain")
                            def lastBuild = upstreamJob?.getLastSuccessfulBuild()
                            
                            if (lastBuild) {
                                echo "� Build encontrado: ${lastBuild.number}"
                                
                                // Intentar leer variables de entorno del build upstream
                                def envVars = lastBuild.getEnvironment()
                                if (envVars.containsKey('DROPLET_IP')) {
                                    env.VM_IP = envVars.get('DROPLET_IP')
                                    echo "✅ IP obtenida desde variables de entorno upstream: ${env.VM_IP}"
                                    ipObtained = true
                                }
                            }
                        } catch (Exception e) {
                            echo "⚠️  No se pudo acceder a variables de entorno upstream: ${e.message}"
                        }
                    }
                    
                    // Prioridad 3: Descargar artefactos usando curl
                    if (!ipObtained) {
                        try {
                            echo "🔍 Intentando descargar artefactos del job de infraestructura..."
                            
                            // Descargar droplet.properties
                            def jobUrl = "${env.JENKINS_URL}job/infra-microservice-app-example/job/infra%252Fmain/lastSuccessfulBuild/artifact/droplet.properties"
                            echo "📥 Descargando droplet.properties desde: ${jobUrl}"
                            
                            def curlResult = sh(
                                script: "curl -s -f --connect-timeout 10 '${jobUrl}' || echo 'CURL_FAILED'",
                                returnStdout: true
                            ).trim()
                            
                            if (curlResult != 'CURL_FAILED' && curlResult != '') {
                                echo "✅ droplet.properties descargado exitosamente"
                                echo "📄 Contenido:\n${curlResult}"
                                
                                // Extraer DROPLET_IP
                                def lines = curlResult.split('\n')
                                for (line in lines) {
                                    if (line.startsWith('DROPLET_IP=')) {
                                        env.VM_IP = line.split('=')[1].trim()
                                        echo "✅ IP extraída de droplet.properties: ${env.VM_IP}"
                                        ipObtained = true
                                        break
                                    }
                                }
                            }
                            
                            // Si no funciona droplet.properties, intentar jenkins-env.properties
                            if (!ipObtained) {
                                echo "🔄 Intentando jenkins-env.properties..."
                                def envJobUrl = "${env.JENKINS_URL}job/infra-microservice-app-example/job/infra%252Fmain/lastSuccessfulBuild/artifact/jenkins-env.properties"
                                
                                def envCurlResult = sh(
                                    script: "curl -s -f --connect-timeout 10 '${envJobUrl}' || echo 'CURL_FAILED'",
                                    returnStdout: true
                                ).trim()
                                
                                if (envCurlResult != 'CURL_FAILED' && envCurlResult != '') {
                                    echo "✅ jenkins-env.properties descargado exitosamente"
                                    echo "📄 Contenido:\n${envCurlResult}"
                                    
                                    def envLines = envCurlResult.split('\n')
                                    for (line in envLines) {
                                        if (line.startsWith('DROPLET_IP=') || line.startsWith('VM_IP_ADDRESS=')) {
                                            env.VM_IP = line.split('=')[1].trim()
                                            echo "✅ IP extraída de jenkins-env.properties: ${env.VM_IP}"
                                            ipObtained = true
                                            break
                                        }
                                    }
                                }
                            }
                            
                        } catch (Exception e) {
                            echo "❌ Error descargando artefactos: ${e.message}"
                        }
                    }
                    
                    // Prioridad 4: Usar build step para disparar job y obtener variables
                    if (!ipObtained) {
                        try {
                            echo "🔄 Intentando obtener IP via build step..."
                            def upstreamBuild = build(
                                job: 'infra-microservice-app-example/infra%2Fmain',
                                wait: false,
                                propagate: false
                            )
                            echo "⚠️  Build step ejecutado, pero no se puede obtener variables dinámicamente"
                        } catch (Exception e) {
                            echo "❌ Error con build step: ${e.message}"
                        }
                    }
                    
                    // Validación final
                    if (!ipObtained || !env.VM_IP || env.VM_IP.trim() == '') {
                        echo "❌ No se pudo obtener la IP de la VM automáticamente"
                        echo ""
                        echo "💡 SOLUCIONES DISPONIBLES:"
                        echo ""
                        echo "   🎯 OPCIÓN 1 - Ejecutar con parámetro (MÁS FÁCIL):"
                        echo "   • Ve a 'Build with Parameters'"
                        echo "   • En campo 'VM_IP' introduce la IP actual de tu VM"
                        echo "   • Ejemplo: 167.172.123.456"
                        echo ""
                        echo "   🔧 OPCIÓN 2 - Verificar job de infraestructura:"
                        echo "   • Ejecutar job 'infra-microservice-app-example/infra/main'"
                        echo "   • Verificar que termine exitosamente"
                        echo "   • Verificar artefactos: droplet.properties y jenkins-env.properties"
                        echo ""
                        echo "   📋 OPCIÓN 3 - Instalar plugins Jenkins:"
                        echo "   • Copy Artifacts Plugin"
                        echo "   • EnvInject Plugin"
                        echo ""
                        
                        // Mostrar información de debug
                        echo "🔍 DEBUG INFO:"
                        echo "   Jenkins URL: ${env.JENKINS_URL}"
                        echo "   Job esperado: infra-microservice-app-example/infra/main"
                        echo "   Parámetro VM_IP: '${params.VM_IP}'"
                        
                        error "❌ VM_IP requerida para continuar. Usa 'Build with Parameters' y especifica la IP manualmente."
                    }
                    
                    // Validar formato de IP
                    if (!env.VM_IP.matches(/\d+\.\d+\.\d+\.\d+/)) {
                        echo "⚠️  IP no tiene formato estándar: ${env.VM_IP}"
                        echo "   Continuando de todas formas..."
                    }
                    
                    echo "✅ VM IP configurada: ${env.VM_IP}"
                    
                    // Configurar URLs de prueba
                    env.FRONTEND_URL = "http://${env.VM_IP}:${env.FRONTEND_PORT}"
                    env.AUTH_API_URL = "http://${env.VM_IP}:${env.AUTH_API_PORT}"
                    env.TODOS_API_URL = "http://${env.VM_IP}:${env.TODOS_API_PORT}"
                    env.ZIPKIN_URL = "http://${env.VM_IP}:${env.ZIPKIN_PORT}"
                    
                    echo "🌐 URLs configuradas:"
                    echo "   Frontend: ${env.FRONTEND_URL}"
                    echo "   Auth API: ${env.AUTH_API_URL}"
                    echo "   Todos API: ${env.TODOS_API_URL}"
                    echo "   Zipkin: ${env.ZIPKIN_URL}"
                }
            }
        }
        
        stage("Verificar Conectividad VM") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                    sh '''
                        set -e
                        echo "Verificando conectividad con VM: $VM_IP"
                        
                        export SSHPASS="$DEPLOY_PASSWORD"
                        
                        # Verificar conectividad SSH
                        sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                            -o ConnectTimeout=10 $VM_USER@$VM_IP 'echo "SSH OK"'
                        
                        # Verificar que Docker está funcionando
                        sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                            $VM_USER@$VM_IP 'docker --version && docker compose version'
                        
                        # Verificar estado de la aplicación
                        sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                            $VM_USER@$VM_IP "cd $APP_PATH && docker compose ps"
                    '''
                }
            }
        }
        
        stage("Health Checks Básicos") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            parallel {
                stage("Frontend Health") {
                    steps {
                        script {
                            sh '''
                                echo "Verificando Frontend en $FRONTEND_URL"
                                chmod +x ./scripts/jenkins-health-check.sh
                                ./scripts/jenkins-health-check.sh "$FRONTEND_URL" "Frontend" $HEALTH_CHECK_TIMEOUT
                            '''
                        }
                    }
                }
                
                stage("Auth API Health") {
                    steps {
                        script {
                            sh '''
                                echo "Verificando Auth API en ${AUTH_API_URL}/version"
                                ./scripts/jenkins-health-check.sh "${AUTH_API_URL}/version" "Auth API" $HEALTH_CHECK_TIMEOUT
                            '''
                        }
                    }
                }
                
                stage("Zipkin Health") {
                    steps {
                        script {
                            sh '''
                                echo "Verificando Zipkin en $ZIPKIN_URL"
                                ./scripts/jenkins-health-check.sh "$ZIPKIN_URL" "Zipkin" $HEALTH_CHECK_TIMEOUT
                            '''
                        }
                    }
                }
            }
        }
        
        stage("Smoke Test Completo") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                sh '''
                    echo "Ejecutando smoke test completo..."
                    chmod +x ./scripts/jenkins-smoke-test.sh
                    ./scripts/jenkins-smoke-test.sh "$VM_IP"
                '''
            }
        }
        
        stage("Pruebas de Integridad") {
            when {
                allOf {
                    anyOf {
                        branch 'master'
                        branch 'main'
                    }
                    anyOf {
                        equals expected: 'FULL', actual: params.TEST_LEVEL
                        equals expected: 'PATTERNS_ONLY', actual: params.TEST_LEVEL
                    }
                }
            }
            parallel {
                stage("Test Retry Pattern") {
                    steps {
                        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                            sh '''
                                echo "Ejecutando test de retry pattern..."
                                chmod +x ./scripts/jenkins-retry-test.sh
                                ./scripts/jenkins-retry-test.sh "$VM_IP"
                            '''
                        }
                    }
                }
                
                stage("Test Circuit Breaker") {
                    steps {
                        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                            sh '''
                                echo "Ejecutando test de circuit breaker..."
                                chmod +x ./scripts/jenkins-cb-test.sh
                                ./scripts/jenkins-cb-test.sh "$VM_IP"
                            '''
                        }
                    }
                }
                
                stage("Test Rate Limiting") {
                    steps {
                        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                            sh '''
                                echo "Ejecutando test de rate limiting..."
                                chmod +x ./scripts/jenkins-rate-limit-test.sh
                                ./scripts/jenkins-rate-limit-test.sh "$VM_IP"
                            '''
                        }
                    }
                }
            }
        }
        
        stage("Test Cache Pattern") {
            when {
                allOf {
                    anyOf {
                        branch 'master'
                        branch 'main'
                    }
                    anyOf {
                        equals expected: 'FULL', actual: params.TEST_LEVEL
                        equals expected: 'PATTERNS_ONLY', actual: params.TEST_LEVEL
                    }
                }
            }
            steps {
                withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                    sh '''
                        echo "Ejecutando test de cache pattern..."
                        chmod +x ./scripts/jenkins-cache-test.sh
                        ./scripts/jenkins-cache-test.sh "$VM_IP"
                    '''
                }
            }
        }
        
        stage("Verificar Logs y Trazas") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                    sh '''
                        echo "Verificando logs y trazas de servicios..."
                        chmod +x ./scripts/jenkins-logs-check.sh
                        ./scripts/jenkins-logs-check.sh "$VM_IP"
                    '''
                }
            }
        }
        
        stage("Reporte de Estado Final") {
            when {
                anyOf {
                    branch 'master'
                    branch 'main'
                }
            }
            steps {
                withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                    sh '''
                        echo "Generando reporte de estado final..."
                        chmod +x ./scripts/jenkins-final-report.sh
                        ./scripts/jenkins-final-report.sh "$VM_IP"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Archivar logs y reportes
                archiveArtifacts artifacts: 'test-results/**/*', allowEmptyArchive: true
                archiveArtifacts artifacts: 'logs/**/*', allowEmptyArchive: true
                
                // Limpiar archivos temporales
                sh 'rm -rf test-results logs droplet.properties || true'
            }
        }
        
        success {
            echo "✅ Todas las pruebas de integridad pasaron exitosamente"
        }
        
        failure {
            echo "❌ Algunas pruebas de integridad fallaron"
            
            // Opcional: obtener logs de emergencia de la VM
            withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
                sh '''
                    echo "Obteniendo logs de emergencia..."
                    export SSHPASS="$DEPLOY_PASSWORD"
                    
                    mkdir -p emergency-logs
                    
                    sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        $VM_USER@$VM_IP "cd $APP_PATH && docker compose logs --tail=100" > emergency-logs/docker-compose.log || true
                    
                    sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        $VM_USER@$VM_IP "cd $APP_PATH && docker compose ps" > emergency-logs/container-status.log || true
                '''
                
                archiveArtifacts artifacts: 'emergency-logs/**/*', allowEmptyArchive: true
            }
        }
        
        unstable {
            echo "⚠️  Algunas pruebas son inestables"
        }
    }
}