# Manual completo de instalación limpia

Este procedimiento parte de una VM sin una instalación previa de Coferlandia CI. No es un manual de actualización. Para instalaciones existentes use [UPGRADE.md](UPGRADE.md).

## 1. Resultado esperado

Al finalizar existirán:

- dos runners GitHub Actions: `coferlandia-ci-01` y `coferlandia-ci-02`;
- dos Docker-in-Docker independientes;
- capacidad para dos jobs simultáneos;
- filesystem CI limitado a 30 GiB por defecto;
- watchdog cada cinco minutos;
- limpieza diaria;
- ningún puerto entrante adicional.

## 2. Requisitos mínimos

- Ubuntu Server 22.04 o 24.04;
- arquitectura `x86_64` o `aarch64/arm64`;
- Docker Engine y `docker compose` funcionando;
- usuario operativo con acceso a Docker y capacidad de usar `sudo`;
- al menos 35 GiB disponibles si se usa `CI_STORAGE_SIZE=30G`;
- salida HTTPS por TCP 443;
- permisos de administrador para registrar runners en la organización o repositorio de GitHub.

Configuración recomendada para la VM compartida utilizada durante el diseño:

- 4 CPU lógicas;
- 16 GiB de RAM o más;
- 60 GiB libres o más antes de instalar.

## 3. Transferir el paquete desde Windows/Git Bash

En la computadora local:

```bash
cd ~/Documents/dev/coferlandia/cofer-ci

scp \
  coferlandia-ci-runner-0.3.1.zip \
  coferlandia-ci-runner-0.3.1.zip.sha256 \
  coferlandia:~/uploads/
```

Conectarse:

```bash
ssh coferlandia
```

Verificar integridad:

```bash
cd ~/uploads
sha256sum -c coferlandia-ci-runner-0.3.1.zip.sha256
```

Resultado esperado:

```text
coferlandia-ci-runner-0.3.1.zip: OK
```

## 4. Instalar utilidades base

```bash
sudo apt update
sudo apt install -y \
  ca-certificates curl git jq unzip \
  util-linux e2fsprogs procps iproute2
```

Verificar Docker:

```bash
docker info
docker compose version
```

Si el usuario no puede ejecutar Docker:

```bash
sudo usermod -aG docker "$USER"
exit
```

Volver a conectarse y repetir `docker info`.

## 5. Extraer el proyecto

```bash
mkdir -p ~/docker-projects
cd ~/docker-projects

rm -rf coferlandia-ci-runner
unzip ~/uploads/coferlandia-ci-runner-0.3.1.zip
cd coferlandia-ci-runner
```

Comprobar:

```bash
cat VERSION
pwd
find . -maxdepth 2 -type f | sort
```

`VERSION` debe mostrar `0.3.1`.

## 6. Crear y revisar `.env`

```bash
cp .env.example .env
nano .env
```

Configuración organizacional típica:

```env
RUNNER_URL=https://github.com/coferlandia
RUNNER_01_NAME=coferlandia-ci-01
RUNNER_02_NAME=coferlandia-ci-02
RUNNER_LABELS=coferlandia-ci,docker
RUNNER_GROUP=Default
CI_STORAGE_SIZE=30G
```

Límites recomendados iniciales:

```env
RUNNER_CPUS=0.50
RUNNER_MEMORY=768m
DIND_CPUS=1.25
DIND_MEMORY=2500m
```

No coloque tokens de GitHub ni secretos de producción en `.env`.

## 7. Validar configuración y relevar la VM

```bash
./scripts/check-prerequisites.sh
docker compose config >/tmp/coferlandia-ci-compose.yml
./scripts/host-survey.sh before
```

Comprobar que no haya puertos publicados:

```bash
docker compose config | grep -n 'published:' || true
```

No debería aparecer ninguno.

## 8. Crear el filesystem limitado

```bash
sudo ./scripts/install-host.sh
```

Verificar:

```bash
findmnt /srv/coferlandia-ci
df -h / /srv/coferlandia-ci
sudo find /srv/coferlandia-ci -maxdepth 2 -printf '%M %u:%g %p\n'
```

Deben existir directorios separados para los índices `01` y `02`.

## 9. Crear los runners en GitHub

Para una organización:

```text
Organization → Settings → Actions → Runners → New self-hosted runner
```

Seleccionar Linux y la arquitectura de la VM. El comando mostrado debe contener exactamente la misma URL configurada en `RUNNER_URL`.

Para un repositorio, el token debe obtenerse desde la configuración de ese repositorio y `RUNNER_URL` debe incluir `OWNER/REPOSITORY`.

## 10. Registrar ambos runners

```bash
./scripts/register-runners.sh
```

El script:

1. construye una sola imagen de runner;
2. inicia `docker-ci-01` y `docker-ci-02`;
3. espera sus certificados TLS;
4. registra el primer runner;
5. registra el segundo runner;
6. inicia ambos listeners persistentes.

Puede reutilizar el primer token para el segundo mientras siga vigente. El script también permite pegar un token diferente.

Éxito esperado:

```text
Runner successfully added
Settings Saved
Registro completado
Listening for Jobs
```

Verificar:

```bash
./scripts/status.sh
docker compose ps
docker compose logs --tail=100 runner-01
docker compose logs --tail=100 runner-02
```

Los cuatro contenedores deben quedar `healthy`.

## 11. Confirmar en GitHub

En la pantalla de runners deben aparecer:

```text
coferlandia-ci-01  Idle
coferlandia-ci-02  Idle
```

Con las etiquetas personalizadas:

```text
coferlandia-ci
docker
```

## 12. Instalar watchdog y cleanup

```bash
sudo ./scripts/install-systemd.sh
```

Configure `/etc/coferlandia-ci-watchdog.env`, incluyendo `GITHUB_MONITOR_TOKEN` si desea monitoreo remoto y self-healing. La política y parámetros están documentados en [MONITORING.md](MONITORING.md).

Verificar:

```bash
systemctl list-timers --all | grep coferlandia-ci
systemctl list-unit-files | grep coferlandia-ci
```

Prueba manual:

```bash
sudo systemctl start coferlandia-ci-watchdog.service
sudo systemctl status coferlandia-ci-watchdog.service --no-pager
```

## 13. Verificación integral

```bash
sudo ./scripts/verify-installation.sh
```

Debe validar los dos registros, los cuatro contenedores, ambos Docker CI, Docker Compose, salida HTTPS, broker de Actions, timers systemd y, cuando el token de monitoreo esté configurado, que GitHub reporte ambos runners `online`.

## 14. Smoke test paralelo

Copie `examples/workflows/runner-smoke-test.yml` a un repositorio autorizado:

```bash
mkdir -p /ruta/al/repo/.github/workflows
cp examples/workflows/runner-smoke-test.yml \
  /ruta/al/repo/.github/workflows/
```

Commit, push y ejecutar manualmente desde GitHub Actions.

El workflow crea dos jobs de una matriz con `max-parallel: 2`. En GitHub deben observarse ejecutándose al mismo tiempo, uno por runner.

Durante la prueba:

```bash
docker compose logs -f runner-01 runner-02
```

Después:

```bash
sudo ./scripts/status.sh
df -h /srv/coferlandia-ci
```

## 15. Relevamiento posterior

```bash
./scripts/host-survey.sh after-idle
ls -lht reports/host-surveys/
```

Para medir durante dos jobs simultáneos:

```bash
./scripts/host-survey.sh during-two-jobs
```

## 16. Prueba de reinicio

```bash
sudo reboot
```

Al volver:

```bash
cd ~/docker-projects/coferlandia-ci-runner
sudo ./scripts/status.sh
sudo ./scripts/verify-installation.sh
systemctl list-timers 'coferlandia-ci-*' --all
```

Los runners deben volver a `Idle` sin registrarlos nuevamente.

## 17. Criterios de aceptación

La instalación está terminada cuando:

- los cuatro contenedores están `healthy`;
- GitHub muestra dos runners `Idle`;
- el smoke test ejecuta dos jobs simultáneos;
- cada Docker CI muestra únicamente sus propios recursos;
- `/srv/coferlandia-ci` está montado;
- los timers están habilitados;
- el monitoreo remoto detecta runners `offline` cuando está configurado;
- no hay puertos públicos nuevos.
