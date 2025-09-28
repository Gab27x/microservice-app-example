pipeline {
    agent any
    
    options { 
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 45, unit: 'MINUTES')
    }
    
    environment {
        // Credenciales para conectar a la VM
        VM_USER = "deploy"
        APP_PATH = "/opt/microservice-app"
        
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
        stage("Obtener IP de VM") {
            steps {
                script {
                    // Obtener la IP de la VM desde el artefacto del job de infraestructura
                    copyArtifacts(
                        projectName: 'infraestructura-microservices', // Ajusta el nombre del job de infra
                        selector: lastSuccessful(),
                        filter: 'droplet.properties'
                    )
                    
                    // Leer la IP del archivo
                    def props = readProperties file: 'droplet.properties'
                    env.VM_IP = props.DROPLET_IP
                    
                    if (!env.VM_IP) {
                        error "No se pudo obtener la IP de la VM del artefacto"
                    }
                    
                    echo "VM IP obtenida: ${env.VM_IP}"
                    
                    // Configurar URLs de prueba
                    env.FRONTEND_URL = "http://${env.VM_IP}:${env.FRONTEND_PORT}"
                    env.AUTH_API_URL = "http://${env.VM_IP}:${env.AUTH_API_PORT}"
                    env.TODOS_API_URL = "http://${env.VM_IP}:${env.TODOS_API_PORT}"
                    env.ZIPKIN_URL = "http://${env.VM_IP}:${env.ZIPKIN_PORT}"
                }
            }
        }
        
        stage("Verificar Conectividad VM") {
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
            steps {
                sh '''
                    echo "Ejecutando smoke test completo..."
                    chmod +x ./scripts/jenkins-smoke-test.sh
                    ./scripts/jenkins-smoke-test.sh "$VM_IP"
                '''
            }
        }
        
        stage("Pruebas de Integridad") {
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