## Guía de VM y Despliegue (DigitalOcean + Docker Compose)

Esta guía documenta, paso a paso, cómo creamos y configuramos la VM para desplegar la aplicación de microservicios del taller, por qué elegimos el proveedor y plan, cómo gestionamos las llaves SSH del equipo, y cómo integramos el despliegue con Jenkins.

### 1. Por qué DigitalOcean y qué plan elegimos

- Elegimos DigitalOcean por simplicidad de uso, precios transparentes y arranque rápido de Droplets.
- Región: Atlanta (más cercana a Colombia) para menor latencia. Alternativa: New York.
- Plan recomendado para demo: Regular SSD $12/mes (2 GB RAM, 1 vCPU, 50 GB SSD). Suficiente para "run-only" de contenedores.
- No usamos volumen adicional ni base de datos administrada: el stack es efímero y Redis es cache/cola.

### 2. Creación del Droplet

En el panel de DO: Create → Droplets

- Imagen: Ubuntu 22.04 (LTS) x64
- Región: Atlanta
- Plan: Regular SSD $12 (2 GB / 1 vCPU / 50 GB SSD)
- Autenticación: SSH Key (sube tu `.pub`)
- Opciones: Monitoring (gratis). Backups opcionales.

### 3. Acceso inicial y usuario de despliegue

Conéctate como `root` la primera vez y crea el usuario `deploy`:

```bash
ssh -i ~/.ssh/do-microservice-app root@<IP_VM>
adduser deploy
usermod -aG sudo deploy
```

Opcional: deshabilitar login de root más adelante.

### 4. Llaves SSH para el equipo

Cada persona genera su propia clave ed25519 con passphrase y agrega la pública en GitHub (para repos) y en la VM (para SSH):

```bash
ssh-keygen -t ed25519 -C "<usuario>@users.noreply.github.com" -f ~/.ssh/do-microservice-app
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/do-microservice-app
cat ~/.ssh/do-microservice-app.pub
```

Agregar su `.pub` al usuario `deploy` en la VM (lo hace un administrador que ya tenga acceso):

```bash
echo 'ssh-ed25519 AAAA... nombre' | sudo tee -a /home/deploy/.ssh/authorized_keys >/dev/null
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

Alias útil en cada laptop (`~/.ssh/config`):

```
Host do-app
  HostName <IP_VM>
  User deploy
  IdentityFile ~/.ssh/do-microservice-app
  IdentitiesOnly yes
```

### 5. Instalación de Docker y Compose

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker deploy
newgrp docker
docker version
docker compose version
```

### 6. Preparar despliegue con Docker Compose

Estructura en la VM:

```bash
sudo mkdir -p /opt/microservice-app
sudo chown -R $(whoami):$(whoami) /opt/microservice-app
cd /opt/microservice-app
```

Variables del despliegue (usamos `.env` para parametrizar el owner del registry):

```bash
cat > .env << 'EOF'
REGISTRY_URL=ghcr.io
REGISTRY_ORG=gab27x   # o oscarmura / andres-chamorro
TAG=staging-latest
EOF
```

Copiar el compose de producción desde el repo local:

```bash
scp docker-compose.prod.yml deploy@<IP_VM>:/opt/microservice-app/docker-compose.yml
```

Desplegar:

```bash
cd /opt/microservice-app
# si los paquetes en GHCR son privados:
# echo <PAT> | docker login ghcr.io -u <usuario> --password-stdin
docker compose pull
docker compose up -d
docker compose ps
```

### 7. Integración con Jenkins

- Jenkinsfile multibranch en el repo: construye imágenes, etiqueta `staging-latest` (develop) / `prod-latest` (main) y despliega por SSH.
- Credenciales en Jenkins:
  - `DEPLOY_SSH` (SSH Username with private key) → usuario `deploy` de la VM.
  - `REGISTRY_CREDENTIALS` (Username/password o token) para el registry si es privado.
- Variables del job: `REGISTRY_URL`, `REGISTRY_ORG`, `DEPLOY_HOST`, `DEPLOY_USER=deploy`, `DEPLOY_PATH=/opt/microservice-app`.

### 8. Seguridad básica

- Firewall (UFW): permitir solo puertos necesarios para la demo (3000, 8000, 8082, 8083, 9411). Redis 6379 solo interno.

```bash
sudo ufw allow 22/tcp
sudo ufw allow 3000,8000,8082,8083,9411/tcp
sudo ufw enable
```

- Deshabilitar SSH de root cuando ya tengas `deploy` operando:

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl reload ssh
```

### 9. Solución de problemas comunes

- `Permission denied (publickey)`: cargar la clave en el agente (`ssh-add`), verificar `~/.ssh/config`, y que la `.pub` esté en `authorized_keys`.
- `Never used` en llave de GitHub: asegurarse de usar remoto SSH (`git@github.com:`) y que la clave ofrecida coincida (ver con `ssh -vT`).
- Imágenes no disponibles: validar `REGISTRY_ORG` y `TAG`, o hacer `docker login` a GHCR.

### 10. Justificación técnica resumida

- Proveedor/plan: DO Regular 2GB por costo/beneficio y simplicidad.
- Acceso: SSH con claves por persona; sin contraseñas, facilita auditoría y revocación.
- Despliegue: Docker Compose con variables `.env`; fácil de parametrizar por owner (`gab27x`, `oscarmura`, `andres-chamorro`).
- CI/CD: Actions para CI y Jenkins para CD; tags por rama (`staging-latest`/`prod-latest`).
- Patrón aplicado: cache-aside en `todos-api` con Redis e invalidación en mutaciones.

