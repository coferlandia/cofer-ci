# Actualización de una instalación existente

Este procedimiento cubre una actualización desde 0.2.x, 0.3.0 o un estado mixto en el que los contenedores activos pertenecen a la topología de dos runners pero el directorio operativo conserva archivos antiguos.

## Objetivo

Actualizar el paquete operativo sin perder:

- `/srv/coferlandia-ci`;
- registros y credenciales existentes de los runners;
- workspaces y cachés persistentes;
- almacenamiento de ambos Docker-in-Docker.

No vuelva a registrar runners que ya aparecen correctamente en GitHub salvo que exista evidencia explícita de corrupción de credenciales.

## 1. Confirmar que no haya jobs en ejecución

Antes de reemplazar archivos:

```bash
gh api /orgs/coferlandia/actions/runners \
  --jq '.runners[] | select(.name | startswith("coferlandia-ci")) | "\(.name) status=\(.status) busy=\(.busy)"'
```

Ambos deben estar `busy=false`.

También puede comprobar workers locales:

```bash
docker exec coferlandia-ci-runner-01 pgrep -af 'Runner.Worker' || true
docker exec coferlandia-ci-runner-02 pgrep -af 'Runner.Worker' || true
```

## 2. Diagnosticar el estado instalado antes de usar Compose

Desde el directorio operativo actual:

```bash
cd ~/docker-projects/coferlandia-ci-runner

cat VERSION 2>/dev/null || true
docker compose config --services

docker inspect -f '{{.Name}} -> {{index .Config.Labels "com.docker.compose.service"}}' \
  coferlandia-ci-runner-01 \
  coferlandia-ci-runner-02 2>/dev/null || true
```

Si `docker compose config --services` muestra sólo `runner` y `docker-ci`, pero los contenedores existentes están asociados a `runner-01`, `runner-02`, `docker-ci-01` y `docker-ci-02`, la instalación está mezclada. **No ejecute `docker compose up`, `down`, `start`, `stop` ni `restart` desde ese directorio antiguo.**

## 3. Respaldar sólo los archivos operativos

El almacenamiento persistente no se mueve.

```bash
cd ~/docker-projects
mv coferlandia-ci-runner \
   "coferlandia-ci-runner.backup-$(date +%Y%m%d-%H%M%S)"
```

Conserve la ruta del backup para recuperar `.env` y facilitar rollback.

## 4. Instalar el paquete nuevo

Con Git:

```bash
cd ~/docker-projects
gh repo clone coferlandia/cofer-ci coferlandia-ci-runner
cd coferlandia-ci-runner
```

O extraiga el ZIP de la versión publicada en ese mismo directorio.

Antes de ejecutar Compose:

```bash
cat VERSION
docker compose config --services
```

La topología esperada es:

```text
docker-ci-01
runner-01
docker-ci-02
runner-02
```

## 5. Recuperar y revisar `.env`

Copie el `.env` del backup:

```bash
cp ../coferlandia-ci-runner.backup-YYYYMMDD-HHMMSS/.env .env
```

Revise que existan o queden correctamente resueltos:

```env
RUNNER_URL=https://github.com/coferlandia
RUNNER_01_NAME=coferlandia-ci-01
RUNNER_02_NAME=coferlandia-ci-02
RUNNER_LABELS=coferlandia-ci,docker
RUNNER_GROUP=Default
CI_STORAGE_ROOT=/srv/coferlandia-ci
```

No copie tokens de registro temporales a `.env`.

Valide:

```bash
./scripts/check-prerequisites.sh
docker compose config >/tmp/coferlandia-ci-compose.yml
```

## 6. Reconciliar los contenedores con el Compose nuevo

Compruebe primero qué contenedores existen:

```bash
docker compose ps -a
```

Si los cuatro servicios ya corresponden al proyecto y los runners están registrados en `/srv/coferlandia-ci`, aplique el Compose nuevo sin borrar almacenamiento:

```bash
docker compose up -d --build
```

No ejecute `docker compose down -v`. Los directorios bajo `/srv/coferlandia-ci` son la fuente persistente del estado del runner y de cada Docker CI.

## 7. Reinstalar systemd desde el directorio nuevo

Las unidades contienen la ruta absoluta del proyecto, por lo que deben regenerarse después de reemplazar el directorio operativo:

```bash
sudo ./scripts/install-systemd.sh
```

Verifique:

```bash
systemctl list-timers 'coferlandia-ci-*' --all
systemctl is-enabled coferlandia-ci-watchdog.timer
systemctl is-enabled coferlandia-ci-cleanup.timer
```

## 8. Configurar monitoreo remoto y self-healing

Revise:

```bash
sudo nano /etc/coferlandia-ci-watchdog.env
sudo chmod 600 /etc/coferlandia-ci-watchdog.env
```

Configuración recomendada:

```env
GITHUB_MONITOR_TOKEN=
GITHUB_SCOPE_TYPE=org
GITHUB_OWNER=coferlandia
RUNNER_OFFLINE_CHECKS_BEFORE_RESTART=2
RUNNER_RESTART_COOLDOWN_SECONDS=1800
```

El token debe permitir leer los runners del scope configurado. Sin ese token, el watchdog conserva controles locales pero no puede detectar el caso `Runner.Listener` vivo + runner remoto `offline`.

## 9. Validación posterior

Ejecute con `sudo` para que pueda leer `/etc/coferlandia-ci-watchdog.env`:

```bash
sudo ./scripts/status.sh
sudo ./scripts/verify-installation.sh
```

Confirme también directamente:

```bash
gh api /orgs/coferlandia/actions/runners \
  --jq '.runners[] | select(.name | startswith("coferlandia-ci")) | "\(.name) status=\(.status) busy=\(.busy) labels=\([.labels[].name] | join(","))"'
```

Ambos runners deben aparecer `online` y, sin jobs activos, `busy=false`.

## 10. Prueba de reboot

Una vez validados los controles anteriores:

```bash
sudo reboot
```

Después del arranque:

```bash
cd ~/docker-projects/coferlandia-ci-runner
sudo ./scripts/status.sh
sudo ./scripts/verify-installation.sh
```

Los dos runners deben regresar `online/Idle` sin re-registro manual.

## 11. Rollback

Si el paquete nuevo presenta un problema antes de modificar el almacenamiento persistente:

1. detenga únicamente los contenedores creados por la versión nueva;
2. renombre el directorio nuevo;
3. restaure el backup del directorio operativo;
4. reinstale las unidades systemd desde el directorio restaurado sólo si esa versión es compatible con la topología activa.

No restaure una versión cuyo `compose.yml` describa `runner`/`docker-ci` únicos sobre una topología activa `runner-01`/`runner-02`. En ese caso use el backup sólo para recuperar configuración y diagnosticar; no ejecute Compose desde él.

## Criterio de éxito

La actualización queda cerrada cuando:

- el directorio operativo y `VERSION` corresponden a la misma versión;
- `docker compose config --services` muestra los cuatro servicios;
- los cuatro contenedores están healthy;
- ambos runners están `online` en GitHub;
- watchdog y cleanup están habilitados;
- el watchdog tiene monitoreo remoto configurado;
- un reboot completo recupera ambos runners sin intervención manual.
