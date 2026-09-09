# Actualización de una instalación existente

Este procedimiento cubre una actualización desde 0.2.x, 0.3.0 o un estado mixto en el que los contenedores activos pertenecen a la topología de dos runners pero el directorio operativo conserva archivos antiguos.

## Objetivo

Actualizar el paquete operativo sin perder:

- `/srv/coferlandia-ci`;
- registros y credenciales existentes cuando la topología persistente sea compatible;
- workspaces y cachés persistentes;
- almacenamiento Docker CI reutilizable cuando corresponda.

No vuelva a registrar runners que ya aparecen correctamente en GitHub salvo que la migración de topología lo requiera o exista evidencia explícita de corrupción de credenciales.

## 1. Confirmar que no haya jobs en ejecución

Antes de reemplazar archivos:

```bash
gh api /orgs/coferlandia/actions/runners \
  --jq '.runners[] | select(.name | startswith("coferlandia-ci")) | "\(.name) status=\(.status) busy=\(.busy)"'
```

Los runners existentes deben estar `busy=false`.

También puede comprobar workers locales de la topología 0.3.x:

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

docker ps --format 'table {{.Names}}\t{{.Status}}'
```

Si existen los contenedores 0.3.x, compruebe además sus labels Compose:

```bash
docker inspect -f '{{.Name}} -> {{index .Config.Labels "com.docker.compose.service"}}' \
  coferlandia-ci-runner-01 \
  coferlandia-ci-runner-02 2>/dev/null || true
```

Clasifique la instalación antes de seguir:

- **0.3.x coherente**: el Compose y los contenedores describen `runner-01`, `runner-02`, `docker-ci-01`, `docker-ci-02`.
- **Estado mixto**: el Compose local muestra sólo `runner` y `docker-ci`, pero los contenedores activos pertenecen a `runner-01`, `runner-02`, `docker-ci-01`, `docker-ci-02`.
- **0.2.x pura**: tanto archivos como contenedores pertenecen a la topología antigua de un runner y un Docker CI.

En un estado mixto, **no ejecute `docker compose up`, `down`, `start`, `stop` ni `restart` desde el directorio antiguo**.

En una 0.2.x pura tampoco asuma que las credenciales del único runner pueden reutilizarse directamente como `runner-01`/`runner-02`: la migración cambia la topología persistente. Conserve `/srv/coferlandia-ci` como backup, pero registre la topología 0.3.x mediante el procedimiento normal si no existen ya los directorios y registros independientes `runner-01` y `runner-02`.

## 3. Respaldar sólo los archivos operativos

El almacenamiento persistente no se mueve ni se borra.

```bash
cd ~/docker-projects
mv coferlandia-ci-runner \
   "coferlandia-ci-runner.backup-$(date +%Y%m%d-%H%M%S)"
```

Conserve la ruta del backup para recuperar `.env` y facilitar rollback.

Para una instalación 0.2.x pura, haga también un inventario de `/srv/coferlandia-ci` antes de crear la topología nueva:

```bash
sudo find /srv/coferlandia-ci -maxdepth 2 -mindepth 1 -printf '%M %u:%g %p\n' | sort
```

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

### 6.1 Estado mixto o 0.3.x existente

Compruebe primero qué contenedores existen:

```bash
docker compose ps -a
```

Si los cuatro servicios ya corresponden al proyecto y los runners están registrados en `/srv/coferlandia-ci/runner-01` y `/srv/coferlandia-ci/runner-02`, aplique el Compose nuevo sin borrar almacenamiento:

```bash
docker compose up -d --build
```

### 6.2 Instalación 0.2.x pura

Si no existen los directorios persistentes independientes de 0.3.x, no fuerce la reutilización del registro único antiguo. Prepare la estructura nueva y registre ambos runners con los scripts actuales:

```bash
sudo ./scripts/install-host.sh
./scripts/register-runners.sh
```

Mantenga el almacenamiento 0.2.x respaldado hasta completar la validación. La migración de caches o workspaces antiguos es opcional y no debe incluir archivos de credenciales del runner entre topologías distintas.

En todos los casos, **no ejecute `docker compose down -v`**. Los directorios bajo `/srv/coferlandia-ci` son persistentes y deben conservarse hasta cerrar la migración.

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

Si el paquete nuevo presenta un problema antes de borrar o transformar almacenamiento persistente:

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
