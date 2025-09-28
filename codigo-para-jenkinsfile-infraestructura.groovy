// ========================================================================
// CÓDIGO PARA AÑADIR AL FINAL DEL JENKINSFILE DE INFRAESTRUCTURA
// Añadir este stage después del stage "Deployment Summary"
// ========================================================================

    stage("Trigger Integration Tests") {
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        script {
          if (env.DROPLET_IP) {
            echo "🚀 Disparando tests de integridad automáticamente..."
            echo "   IP de la VM: ${env.DROPLET_IP}"
            echo "   Job de tests: microservice-app-example/master"
            
            try {
              // Disparar el job de tests con la IP como parámetro
              def testsBuild = build(
                job: 'microservice-app-example/master',
                parameters: [
                  string(name: 'VM_IP', value: env.DROPLET_IP),
                  string(name: 'TEST_LEVEL', value: 'FULL')
                ],
                wait: false, // No esperar a que termine para no bloquear
                propagate: false // No fallar si los tests fallan
              )
              
              def testsJobUrl = "${env.JENKINS_URL}job/microservice-app-example/job/master/${testsBuild.number}/"
              
              echo "✅ Tests de integridad disparados exitosamente!"
              echo "🔗 Ver progreso en: ${testsJobUrl}"
              echo "📋 Parámetros enviados:"
              echo "   • VM_IP = ${env.DROPLET_IP}"
              echo "   • TEST_LEVEL = FULL"
              
              // Actualizar el archivo de resumen con info de tests
              def summaryContent = readFile('deployment-summary.txt')
              summaryContent += """

Integration Tests:
- Status: TRIGGERED
- Job: microservice-app-example/master
- Build: #${testsBuild.number}
- URL: ${testsJobUrl}
- VM_IP: ${env.DROPLET_IP}
- Test Level: FULL
"""
              writeFile file: 'deployment-summary.txt', text: summaryContent
              archiveArtifacts artifacts: "deployment-summary.txt", fingerprint: true
              
            } catch (Exception e) {
              echo "⚠️  No se pudo disparar los tests automáticamente: ${e.message}"
              echo "💡 Posibles causas:"
              echo "   • Job 'microservice-app-example/master' no existe"
              echo "   • Permisos insuficientes"
              echo "   • Job de tests deshabilitado"
              echo ""
              echo "🔧 Solución manual:"
              echo "   1. Ve al job: microservice-app-example/master"
              echo "   2. Click en 'Build with Parameters'"
              echo "   3. VM_IP = ${env.DROPLET_IP}"
              echo "   4. TEST_LEVEL = FULL"
              echo "   5. Ejecutar"
            }
          } else {
            echo "⚠️  No hay DROPLET_IP disponible, no se pueden disparar los tests"
          }
        }
      }
    }

// ========================================================================
// MODIFICACIÓN AL POST SECTION DEL JENKINSFILE DE INFRAESTRUCTURA
// Reemplazar el post { success { ... } } existente con este:
// ========================================================================

  post {
    always {
      script {
        if (env.DROPLET_IP) {
          echo "🏁 Pipeline finalizado. IP de la VM disponible: ${env.DROPLET_IP}"
        }
      }
    }
    success {
      script {
        echo "✅ Pipeline de infraestructura ejecutado exitosamente!"
        if (env.DROPLET_IP) {
          echo """
╔═══════════════════════════════════════════════════════════════════
║ 🎉 INFRAESTRUCTURA LISTA
╠═══════════════════════════════════════════════════════════════════
║ 🌐 Tu aplicación está disponible en:
║    • Frontend: http://${env.DROPLET_IP}:3000
║    • Zipkin: http://${env.DROPLET_IP}:9411
║    • Backup: http://${env.DROPLET_IP}:80
║
║ 🧪 Tests de integridad:
║    • Se han disparado automáticamente
║    • Revisa el job: microservice-app-example/master
║    • IP configurada: ${env.DROPLET_IP}
║
║ 📋 Próximos pasos:
║    1. Verificar que los tests pasen ✅
║    2. Revisar logs de la aplicación
║    3. Monitorear métricas en Zipkin
╚═══════════════════════════════════════════════════════════════════
          """
        }
      }
    }
    failure {
      script {
        echo "❌ Pipeline falló. Revisa los logs para más detalles."
      }
    }
  }