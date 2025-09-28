# 🔧 Plugins Necesarios para Jenkins

Para que el pipeline funcione completamente, necesitas instalar estos plugins en Jenkins:

## 📦 Plugins Requeridos

### 1. **Pipeline Plugin** (Ya debería estar instalado)
- **Nombre**: Pipeline
- **ID**: workflow-aggregator
- **Descripción**: Plugin base para pipelines declarativos

### 2. **EnvInject Plugin** (Recomendado para variables de entorno)
- **Nombre**: Environment Injector Plugin
- **ID**: envinject
- **Descripción**: Permite inyectar variables de entorno entre stages y jobs

### 3. **Copy Artifacts Plugin** (Opcional pero útil)
- **Nombre**: Copy Artifact Plugin
- **ID**: copyartifact
- **Descripción**: Copia artefactos entre jobs

### 4. **Build Trigger Plugin** (Ya debería estar instalado)
- **Nombre**: Build Trigger Plugin
- **ID**: build-trigger-plugin
- **Descripción**: Para triggers upstream/downstream

## 🚀 Instalación de Plugins

### Método 1: Desde la Interfaz Web
1. Ve a **Manage Jenkins** → **Manage Plugins**
2. En la pestaña **Available**, busca cada plugin
3. Marca la casilla e instala
4. Reinicia Jenkins cuando sea necesario

### Método 2: Desde Jenkins CLI
```bash
# Si tienes acceso CLI
java -jar jenkins-cli.jar -s http://jenkins.icesi.tech/ install-plugin envinject
java -jar jenkins-cli.jar -s http://jenkins.icesi.tech/ install-plugin copyartifact
```

### Método 3: Usando Docker (si Jenkins está en Docker)
```bash
# Añadir al Dockerfile de Jenkins
RUN jenkins-plugin-cli --plugins envinject copyartifact
```

## 🎯 Configuración Post-Instalación

### Para EnvInject Plugin:
1. En la configuración del job de infraestructura:
   - **Build Environment** → **Inject environment variables**
   - **Properties Content**: 
     ```
     DROPLET_IP=${DROPLET_IP}
     VM_IP_ADDRESS=${VM_IP_ADDRESS}
     ```

### Para Copy Artifacts Plugin:
1. En el job de tests, añadir step:
   - **Build Steps** → **Copy artifacts from another project**
   - **Project name**: `infra-microservice-app-example/infra/main`
   - **Artifacts to copy**: `droplet.properties,jenkins-env.properties`

## 🔍 Verificación de Plugins Instalados

Para verificar que los plugins están instalados:

1. **Via Web UI**:
   - **Manage Jenkins** → **Manage Plugins** → **Installed**
   - Buscar: envinject, copyartifact

2. **Via Groovy Console** (Manage Jenkins → Script Console):
   ```groovy
   def plugins = Jenkins.instance.pluginManager.plugins
   plugins.findAll { it.shortName.contains('envinject') || it.shortName.contains('copyartifact') }
       .each { println "${it.shortName}: ${it.version}" }
   ```

## 🚨 Si no puedes instalar plugins

Si no tienes permisos para instalar plugins, el pipeline **debería funcionar de todas formas** usando:

### Alternativa 1: Parámetros manuales
- Ejecutar siempre con **"Build with Parameters"**
- Introducir manualmente la IP de la VM

### Alternativa 2: Variables globales de Jenkins
1. **Manage Jenkins** → **Configure System**
2. **Global Properties** → **Environment variables**
3. Añadir: `DROPLET_IP = tu_ip_actual`

### Alternativa 3: Archivo compartido
- Usar un archivo en `/tmp/` o `/var/jenkins_home/` compartido entre jobs

## 🎯 Configuración Recomendada Final

### En el Job de Infraestructura:
```groovy
// Al final del pipeline, añadir:
stage("Set Global Variables") {
    steps {
        script {
            // Establecer variables globales para otros jobs
            def globalProps = Jenkins.instance.globalNodeProperties
            def envVars = globalProps.get(hudson.slaves.EnvironmentVariablesNodeProperty.class)
            
            if (envVars == null) {
                envVars = new hudson.slaves.EnvironmentVariablesNodeProperty()
                globalProps.add(envVars)
            }
            
            envVars.envVars.put('CURRENT_DROPLET_IP', env.DROPLET_IP)
            Jenkins.instance.save()
            
            echo "✅ Variable global establecida: CURRENT_DROPLET_IP = ${env.DROPLET_IP}"
        }
    }
}
```

### En el Job de Tests:
```groovy
// En environment section:
environment {
    VM_IP = "${env.CURRENT_DROPLET_IP ?: params.VM_IP ?: 'NO_IP'}"
}
```

## 📋 Resumen de Prioridades

1. **MÍNIMO NECESARIO**: Ningún plugin adicional (usar parámetros manuales)
2. **RECOMENDADO**: EnvInject Plugin
3. **IDEAL**: EnvInject + Copy Artifacts

¿Qué método prefieres implementar?