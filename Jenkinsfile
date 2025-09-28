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
                echo "📥 Copiando droplet.properties del job de infraestructura..."
                copyArtifacts(
                    projectName: 'infra-microservice-app-example/infra%2Fmain',
                    selector: lastSuccessful(),
                    filter: 'droplet.properties',
                    fingerprintArtifacts: true
                )


                def ipValue = sh(script: 'grep "^DROPLET_IP=" droplet.properties | cut -d= -f2', returnStdout: true).trim()
                if (!ipValue) {
                    error("❌ No se pudo obtener DROPLET_IP desde droplet.properties")
                }

                env.VM_IP = ipValue
                echo "✅ VM IP obtenida vía Copy Artifact: ${env.VM_IP}"

                // Configurar URLs de prueba
                env.FRONTEND_URL = "http://${env.VM_IP}:${env.FRONTEND_PORT}"
                env.AUTH_API_URL = "http://${env.VM_IP}:${env.AUTH_API_PORT}"
                env.TODOS_API_URL = "http://${env.VM_IP}:${env.TODOS_API_PORT}"
                env.ZIPKIN_URL   = "http://${env.VM_IP}:${env.ZIPKIN_PORT}"

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