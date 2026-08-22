# Deploy de Coferlandia CI Runner en la VM

Esta guía instala `coferlandia-ci-runner` como un proyecto Docker independiente dentro de la VM de Coferlandia.

## Datos del entorno

- IP pública de la VM: `129.146.58.133`
- Usuario SSH: `ubuntu`
- Puerto SSH: `22`
- ZIP local: `~/coferlandia-ci-runner-0.2.0.zip`
- Carpeta local de claves: `~/keys/`
- Carpeta remota de proyectos Docker: `/home/ubuntu/docker-projects/`
- Carpeta final del proyecto: `/home/ubuntu/docker-projects/coferlandia-ci-runner/`
- URL de la organización GitHub: `https://github.com/coferlandia`
- Nombre del runner: `coferlandia-ci-01`

> Los comandos del lado de Windows están escritos para Git Bash.

---

## 1. Preparar las variables locales en Git Bash

Abrir Git Bash y posicionarse en el home:

```bash
cd ~
```

Revisar el nombre de la clave privada:

```bash
ls -lah ./keys
```

La clave privada es el archivo que **no** termina en `.pub`.

Definir las variables:

```bash
export VM_HOST="129.146.58.133"
export VM_USER="ubuntu"
export VM_PORT="22"
export SSH_KEY="./keys/coferlandia.key"
export ZIP_FILE="./coferlandia-ci-runner-0.2.0.zip"
```

Proteger la clave privada:

```bash
chmod 600 "$SSH_KEY"
```

Comprobar que existen la clave y el ZIP:

```bash
ls -lh "$SSH_KEY" "$ZIP_FILE"
```

Opcionalmente, generar un checksum local:

```bash
cd ~
sha256sum coferlandia-ci-runner-0.2.0.zip \
  > coferlandia-ci-runner-0.2.0.zip.sha256
```

---

## 2. Probar la conexión SSH

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST"
```

En el primer acceso, SSH puede pedir confirmar la huella del servidor:

```text
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Responder:

```text
yes
```

Una vez dentro, comprobar el usuario y el host:

```bash
whoami
hostname
pwd
```

El usuario debería ser `ubuntu` y el home `/home/ubuntu`.

Salir temporalmente:

```bash
exit
```

---

## 3. Crear las carpetas remotas

Desde Git Bash:

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST" \
  'mkdir -p "$HOME/uploads" "$HOME/docker-projects"'
```

Verificar:

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST" \
  'ls -ld "$HOME/uploads" "$HOME/docker-projects"'
```

---

## 4. Subir el ZIP a la VM

Desde Git Bash:

```bash
scp \
  -P "$VM_PORT" \
  -i "$SSH_KEY" \
  "$ZIP_FILE" \
  "$VM_USER@$VM_HOST:~/uploads/"
```

Si se creó el checksum, subirlo también:

```bash
scp \
  -P "$VM_PORT" \
  -i "$SSH_KEY" \
  "$HOME/coferlandia-ci-runner-0.2.0.zip.sha256" \
  "$VM_USER@$VM_HOST:~/uploads/"
```

Comprobar remotamente:

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST" \
  'ls -lh "$HOME/uploads/coferlandia-ci-runner-0.2.0.zip"*'
```

---

## 5. Entrar a la VM

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST"
```

A partir de esta sección, todos los comandos se ejecutan dentro de la VM.

---

## 6. Verificar el paquete

```bash
cd ~/uploads
ls -lh coferlandia-ci-runner-0.2.0.zip*
```

Si se subió el checksum:

```bash
sha256sum -c coferlandia-ci-runner-0.2.0.zip.sha256
```

El resultado esperado es:

```text
coferlandia-ci-runner-0.2.0.zip: OK
```

Sin archivo de checksum, obtener al menos el hash para conservarlo:

```bash
sha256sum coferlandia-ci-runner-0.2.0.zip
```

---

## 7. Revisar el estado general de la VM

Antes de instalar paquetes o crear contenedores:

```bash
hostnamectl
uname -a
nproc
free -h
df -h /
df -ih /
lsblk -f
uptime
```

Revisar Docker:

```bash
docker version
docker compose version
docker info
```

Revisar el consumo actual de los contenedores existentes:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker stats --no-stream
docker system df
```

Revisar puertos publicados antes del deploy:

```bash
sudo ss -lntup
```

Revisar servicios fallidos:

```bash
systemctl --failed
```

> Guardar visualmente cualquier anomalía existente antes de atribuirla al nuevo runner.

---

## 8. Instalar utilidades necesarias

```bash
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  git \
  jq \
  unzip \
  util-linux \
  e2fsprogs \
  procps \
  iproute2
```

Verificar nuevamente Docker:

```bash
docker info
docker compose version
```

Si aparece un error de permisos sobre `/var/run/docker.sock`:

```bash
sudo usermod -aG docker "$USER"
exit
```

Luego volver a entrar desde Git Bash:

```bash
ssh -p "$VM_PORT" -i "$SSH_KEY" "$VM_USER@$VM_HOST"
```

Y confirmar:

```bash
docker info
```

> No montar nunca `/var/run/docker.sock` dentro del runner. El proyecto utiliza un Docker interno exclusivo para CI.

---

## 9. Extraer el proyecto Docker

```bash
cd ~/docker-projects
```

Si ya existe una instalación anterior, respaldarla:

```bash
if [ -d coferlandia-ci-runner ]; then
  mv coferlandia-ci-runner \
    "coferlandia-ci-runner.backup-$(date +%Y%m%d-%H%M%S)"
fi
```

Extraer el ZIP:

```bash
unzip ~/uploads/coferlandia-ci-runner-0.2.0.zip
```

Entrar al proyecto:

```bash
cd ~/docker-projects/coferlandia-ci-runner
```

Comprobar la versión y los archivos:

```bash
cat VERSION
find . -maxdepth 2 -type f | sort
```

La versión esperada es:

```text
0.2.0
```

Asegurar permisos de ejecución:

```bash
chmod +x scripts/*.sh hooks/*.sh runner/*.sh
```

---

## 10. Generar el relevamiento previo automatizado

Este paso debe realizarse **antes** de ejecutar `install-host.sh` o levantar contenedores.

```bash
cd ~/docker-projects/coferlandia-ci-runner
./scripts/host-survey.sh before
```

Listar los informes:

```bash
ls -lh reports/host-surveys/
```

Abrir el informe humano:

```bash
less reports/host-surveys/*-before.txt
```

Salir de `less` con:

```text
q
```

El relevamiento incluye CPU, carga, memoria, swap, discos, inodos, Docker, contenedores, puertos y servicios fallidos.

---

## 11. Crear la configuración del runner

```bash
cp .env.example .env
nano .env
```

Usar inicialmente esta configuración:

```env
COMPOSE_PROJECT_NAME=coferlandia-ci

CI_STORAGE_ROOT=/srv/coferlandia-ci
CI_STORAGE_IMAGE=/var/lib/coferlandia-ci.img
CI_STORAGE_SIZE=30G

RUNNER_URL=https://github.com/coferlandia
RUNNER_NAME=coferlandia-ci-01
RUNNER_LABELS=coferlandia-ci,docker
RUNNER_GROUP=Default
RUNNER_WORKDIR=_work

RUNNER_CPUS=0.75
RUNNER_MEMORY=1g
RUNNER_MEMORY_RESERVATION=256m
RUNNER_PIDS_LIMIT=256

DIND_CPUS=2.0
DIND_MEMORY=4g
DIND_MEMORY_RESERVATION=512m
DIND_PIDS_LIMIT=1024
DIND_SHM_SIZE=512m

DISK_WARN_PERCENT=75
DISK_AGGRESSIVE_PERCENT=82
DISK_EMERGENCY_PERCENT=90
DISK_RECOVERY_PERCENT=70
HOST_DISK_WARN_PERCENT=85
HOST_DISK_EMERGENCY_PERCENT=92

IMAGE_RETENTION_HOURS=168
PACKAGE_CACHE_RETENTION_DAYS=30
WORKSPACE_RETENTION_DAYS=7
BUILDKIT_CACHE_KEEP=6GB
BUILDKIT_CACHE_EMERGENCY_KEEP=1GB
```

No es necesario borrar las demás variables del archivo; solamente comprobar que estos valores sean correctos.

Guardar en `nano`:

```text
Ctrl+O
Enter
Ctrl+X
```

Revisar la configuración final:

```bash
grep -vE '^[[:space:]]*(#|$)' .env
```

> Los límites son máximos, no reservas. El Docker de CI puede usar hasta 2 CPU y 4 GB de RAM cuando un job realmente los necesita.

---

## 12. Crear el almacenamiento limitado para CI

Antes de crear el filesystem, revisar el espacio disponible:

```bash
df -h /
```

Ejecutar:

```bash
sudo ./scripts/install-host.sh
```

El script crea un filesystem ext4 limitado, montado en:

```text
/srv/coferlandia-ci
```

Verificar:

```bash
findmnt /srv/coferlandia-ci
df -h /srv/coferlandia-ci
sudo grep coferlandia-ci /etc/fstab
```

El límite configurado es de 30 GB. Aunque falle una limpieza, CI no debería poder llenar el resto del filesystem más allá de ese contenedor lógico.

---

## 13. Comprobar prerrequisitos del proyecto

```bash
./scripts/check-prerequisites.sh
```

No continuar si el script informa errores.

---

## 14. Obtener el token temporal de GitHub

En el navegador, ingresar a la organización Coferlandia:

```text
https://github.com/organizations/coferlandia/settings/actions/runners
```

Ruta equivalente en la interfaz:

```text
Coferlandia
→ Settings
→ Actions
→ Runners
→ New self-hosted runner
```

Seleccionar Linux y la arquitectura correspondiente si GitHub lo solicita.

No es necesario copiar los comandos de descarga que muestra GitHub. El proyecto ya contiene el runner.

Copiar únicamente el token temporal que aparece en el comando similar a:

```text
./config.sh --url https://github.com/coferlandia --token XXXXX
```

El token es el valor que aparece después de `--token`.

---

## 15. Registrar y arrancar el runner

Dentro de la VM:

```bash
cd ~/docker-projects/coferlandia-ci-runner
./scripts/register-runner.sh
```

El script solicitará:

```text
Token temporal de registro:
```

Pegar el token y presionar Enter. El token no se mostrará en pantalla.

El proceso:

1. construye la imagen del runner;
2. inicia el Docker interno de CI;
3. espera que Docker CI esté saludable;
4. registra el runner en GitHub;
5. arranca el contenedor persistente;
6. muestra el estado final.

Comprobar:

```bash
./scripts/status.sh
```

También revisar:

```bash
docker compose ps
docker compose logs runner --tail=100
docker compose logs docker-ci --tail=100
```

En GitHub, el runner debería aparecer como:

```text
coferlandia-ci-01 — Idle
```

---

## 16. Verificar que no se publicaron puertos

El proyecto no necesita ningún puerto entrante nuevo.

Comprobar Compose:

```bash
docker compose ps
```

Revisar puertos del host:

```bash
sudo ss -lntup
```

No debe aparecer ninguna publicación como:

```text
0.0.0.0:2376
[::]:2376
```

No agregar reglas nuevas para el runner en:

- OCI Security Lists;
- OCI Network Security Groups;
- UFW;
- router o firewall externo.

Flujos requeridos:

| Origen | Destino | Puerto | Tipo |
|---|---|---:|---|
| Administrador | VM | TCP 22 | Entrante, SSH ya existente |
| Runner | GitHub | TCP 443 | Saliente |
| Runner | registries y paquetes | TCP 443 | Saliente |
| Watchdog | Telegram | TCP 443 | Saliente |
| Runner | Docker CI | TCP 2376 | Sólo red Docker interna |

Probar conectividad saliente:

```bash
curl -I https://github.com
curl -I https://api.github.com
curl -I https://api.telegram.org
```

Desde el runner:

```bash
docker compose exec -T runner curl -I https://api.github.com
```

---

## 17. Instalar watchdog y limpieza automática

```bash
sudo ./scripts/install-systemd.sh
```

Verificar timers:

```bash
systemctl list-timers 'coferlandia-ci-*' --all
```

Verificar unidades:

```bash
systemctl status coferlandia-ci-watchdog.timer --no-pager
systemctl status coferlandia-ci-cleanup.timer --no-pager
```

El watchdog se ejecuta periódicamente y la limpieza se ejecuta diariamente.

---

## 18. Configurar alertas por Telegram

### 18.1 Crear o reutilizar un bot

En Telegram, abrir `@BotFather`, crear el bot y obtener el token.

Abrir luego el chat con el bot y enviar:

```text
/start
```

### 18.2 Descubrir el chat ID

En la VM:

```bash
./scripts/discover-telegram-chat-id.sh
```

El script pedirá el token del bot. Copiar el valor `chat_id` que devuelve.

### 18.3 Guardar los secretos

```bash
sudo nano /etc/coferlandia-ci-watchdog.env
```

Completar:

```env
TELEGRAM_BOT_TOKEN=<TOKEN_DEL_BOT>
TELEGRAM_CHAT_ID=<CHAT_ID>

GITHUB_MONITOR_TOKEN=
GITHUB_SCOPE_TYPE=org
GITHUB_OWNER=coferlandia
GITHUB_REPOSITORY=
MONITORED_RUNNER_NAME=coferlandia-ci-01
ALERT_REPEAT_SECONDS=3600
```

La consulta remota de GitHub puede quedar desactivada inicialmente dejando `GITHUB_MONITOR_TOKEN` vacío.

Proteger el archivo:

```bash
sudo chown root:root /etc/coferlandia-ci-watchdog.env
sudo chmod 600 /etc/coferlandia-ci-watchdog.env
```

Probar Telegram:

```bash
sudo ./scripts/test-telegram.sh
```

Forzar una ejecución del watchdog:

```bash
sudo systemctl start coferlandia-ci-watchdog.service
```

Revisar el resultado:

```bash
journalctl \
  -u coferlandia-ci-watchdog.service \
  --since '10 minutes ago' \
  --no-pager
```

---

## 19. Ejecutar la verificación integral local

```bash
./scripts/verify-installation.sh
```

Debe validar:

- Docker host;
- filesystem de CI montado;
- registro local del runner;
- contenedor runner saludable;
- Docker interno de CI;
- Docker Compose dentro del runner;
- salida HTTPS a GitHub;
- salida HTTPS a Telegram.

Ejecutar también:

```bash
./scripts/status.sh
```

---

## 20. Generar el relevamiento posterior en reposo

Esperar entre dos y cinco minutos después del arranque:

```bash
sleep 180
```

Generar el informe posterior:

```bash
./scripts/host-survey.sh after-idle
```

Seleccionar las métricas:

```bash
BEFORE_METRICS="$(
  ls -1t reports/host-surveys/*-before.metrics |
  head -n1
)"

AFTER_METRICS="$(
  ls -1t reports/host-surveys/*-after-idle.metrics |
  head -n1
)"
```

Comparar:

```bash
./scripts/compare-host-surveys.sh \
  "$BEFORE_METRICS" \
  "$AFTER_METRICS" \
  | tee reports/host-surveys/comparison-before-after-idle.txt
```

Revisar:

```bash
cat reports/host-surveys/comparison-before-after-idle.txt
```

Prestar especial atención a:

- memoria disponible;
- swap utilizada;
- disco raíz;
- filesystem `/srv/coferlandia-ci`;
- cantidad de contenedores e imágenes;
- reinicios del runner y Docker CI;
- servicios fallidos;
- nuevos puertos en escucha.

---

## 21. Configurar un workflow de prueba

En un repositorio confiable de GitHub, crear:

```text
.github/workflows/self-hosted-runner-smoke-test.yml
```

Contenido recomendado:

```yaml
name: Self-hosted runner smoke test

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  smoke-test:
    runs-on: [self-hosted, linux, coferlandia-ci]
    timeout-minutes: 10

    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          clean: true

      - name: System information
        run: |
          uname -a
          free -h
          df -h
          docker version
          docker compose version
          docker info

      - name: Test Docker container
        run: docker run --rm hello-world
```

Hacer commit y push. Luego ejecutar:

```text
GitHub
→ Actions
→ Self-hosted runner smoke test
→ Run workflow
```

---

## 22. Medir la VM durante el primer job

Mientras el workflow está ejecutándose, dentro de la VM:

```bash
./scripts/host-survey.sh during-ci
```

Observar recursos en tiempo real:

```bash
docker stats \
  coferlandia-ci-runner \
  coferlandia-ci-docker
```

En otra terminal:

```bash
watch -n 2 'free -h; echo; df -h / /srv/coferlandia-ci'
```

Salir de `watch` con `Ctrl+C`.

Cuando termine el job:

```bash
./scripts/status.sh
./scripts/host-survey.sh after-first-job
```

Comparar el estado previo con el uso durante CI:

```bash
DURING_METRICS="$(
  ls -1t reports/host-surveys/*-during-ci.metrics |
  head -n1
)"

./scripts/compare-host-surveys.sh \
  "$BEFORE_METRICS" \
  "$DURING_METRICS" \
  | tee reports/host-surveys/comparison-before-during-ci.txt
```

---

## 23. Comandos habituales de operación

Entrar al proyecto:

```bash
cd ~/docker-projects/coferlandia-ci-runner
```

Estado general:

```bash
./scripts/status.sh
```

Contenedores:

```bash
docker compose ps
```

Logs del runner:

```bash
docker compose logs runner --tail=200
```

Logs del Docker CI:

```bash
docker compose logs docker-ci --tail=200
```

Logs en vivo:

```bash
docker compose logs -f
```

Logs internos del runner:

```bash
sudo ls -lah /srv/coferlandia-ci/runner/_diag
```

Watchdog:

```bash
journalctl \
  -u coferlandia-ci-watchdog.service \
  --since today \
  --no-pager
```

Limpieza:

```bash
journalctl \
  -u coferlandia-ci-cleanup.service \
  --since today \
  --no-pager
```

Uso de almacenamiento:

```bash
df -h /srv/coferlandia-ci
./scripts/status.sh
```

Reiniciar el stack:

```bash
./scripts/restart.sh
```

Detener:

```bash
./scripts/stop.sh
```

Arrancar:

```bash
./scripts/start.sh
```

Actualizar imágenes cuando el runner esté idle:

```bash
./scripts/update.sh
```

---

## 24. Política esperada de limpieza

Después de cada job se eliminan:

- contenedores temporales de tests;
- redes temporales;
- volúmenes temporales;
- procesos residuales;
- archivos transitorios del job.

Se conservan dentro de límites:

- checkout físico del repositorio;
- cachés NuGet;
- cachés npm;
- cachés pip;
- tool cache;
- capas útiles de Docker y BuildKit.

Esto acelera la secuencia:

```text
test falla
→ corrección
→ nuevo commit
→ nuevo job
```

sin reconstruir innecesariamente todas las dependencias.

La limpieza automática se vuelve más agresiva al alcanzar los umbrales de almacenamiento definidos en `.env`.

---

## 25. Copiar los relevamientos a Windows

Salir de la VM:

```bash
exit
```

Desde Git Bash:

```bash
mkdir -p ~/coferlandia-ci-surveys

scp \
  -P "$VM_PORT" \
  -i "$SSH_KEY" \
  -r \
  "$VM_USER@$VM_HOST:~/docker-projects/coferlandia-ci-runner/reports/host-surveys/" \
  ~/coferlandia-ci-surveys/
```

Listar los archivos descargados:

```bash
find ~/coferlandia-ci-surveys -type f -maxdepth 3 -print
```

---

## 26. Verificación después de reiniciar la VM

Cuando resulte conveniente probar persistencia:

```bash
sudo reboot
```

Volver a conectarse después del reinicio:

```bash
ssh \
  -p "$VM_PORT" \
  -i "$SSH_KEY" \
  "$VM_USER@$VM_HOST"
```

Verificar:

```bash
cd ~/docker-projects/coferlandia-ci-runner
./scripts/status.sh
systemctl list-timers 'coferlandia-ci-*' --all
findmnt /srv/coferlandia-ci
```

En GitHub, el runner debe volver a aparecer como `Idle`.

---

## 27. Diagnóstico rápido ante una falla

Ejecutar en este orden:

```bash
cd ~/docker-projects/coferlandia-ci-runner

./scripts/status.sh

docker compose ps

docker compose logs runner --tail=300

docker compose logs docker-ci --tail=300

sudo ls -lah /srv/coferlandia-ci/runner/_diag

df -h / /srv/coferlandia-ci

free -h

systemctl --failed

journalctl \
  -u coferlandia-ci-watchdog.service \
  --since '1 hour ago' \
  --no-pager
```

Interpretación básica:

- runner `offline` en GitHub: revisar logs `runner` y conectividad HTTPS;
- `docker-ci` unhealthy: revisar sus logs y el espacio disponible;
- `No space left on device`: revisar `/srv/coferlandia-ci` y ejecutar la limpieza controlada;
- reinicios frecuentes: revisar memoria, límites y eventos OOM;
- job en cola indefinidamente: confirmar etiquetas `self-hosted`, `linux`, `coferlandia-ci`;
- error de permisos Docker: revisar membresía del usuario `ubuntu` en el grupo `docker`.

---

## 28. Desinstalación segura

Primero desregistrar el runner:

```bash
cd ~/docker-projects/coferlandia-ci-runner
./scripts/unregister-runner.sh
```

Eliminar timers y servicios:

```bash
sudo ./scripts/uninstall-systemd.sh
```

Detener el stack:

```bash
./scripts/stop.sh
```

Eliminar el almacenamiento solamente si se confirma que ya no se necesita:

```bash
sudo umount /srv/coferlandia-ci

sudo sed -i \
  '\|/var/lib/coferlandia-ci.img /srv/coferlandia-ci|d' \
  /etc/fstab

sudo rm -f /var/lib/coferlandia-ci.img
sudo rmdir /srv/coferlandia-ci
```

Finalmente, archivar o eliminar el proyecto:

```bash
cd ~/docker-projects
mv coferlandia-ci-runner \
  "coferlandia-ci-runner.removed-$(date +%Y%m%d-%H%M%S)"
```

---

## Checklist final

- [ ] La conexión SSH a `129.146.58.133` funciona.
- [ ] El ZIP fue subido y verificado.
- [ ] El proyecto quedó en `~/docker-projects/coferlandia-ci-runner`.
- [ ] Se generó el relevamiento `before`.
- [ ] `.env` contiene la organización y los límites correctos.
- [ ] `/srv/coferlandia-ci` está montado y limitado a 30 GB.
- [ ] El runner aparece `Idle` en GitHub.
- [ ] `runner` y `docker-ci` aparecen `healthy`.
- [ ] No se publicó ningún puerto nuevo.
- [ ] El watchdog y el cleanup tienen timers activos.
- [ ] La prueba de Telegram llegó correctamente.
- [ ] `verify-installation.sh` finalizó sin errores.
- [ ] Se generó y comparó el relevamiento `after-idle`.
- [ ] El smoke test se ejecutó correctamente.
- [ ] Se midió el consumo durante el primer job.
- [ ] Los informes fueron copiados a Windows para revisión.
