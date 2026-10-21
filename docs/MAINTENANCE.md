# Mantenimiento y limpieza

## Estado

```bash
./scripts/status.sh
docker compose ps
docker compose logs --tail=200 runner-01 runner-02
```

## Limpieza por job

Cada runner ejecuta hooks sobre su propio Docker CI:

- elimina contenedores residuales;
- elimina redes no usadas;
- elimina volúmenes no usados;
- conserva imágenes y build cache recientes.

La separación por daemon impide que el hook del runner 1 afecte un job del runner 2.

## Limpieza periódica

```bash
sudo ./scripts/cleanup.sh
```

El timer ejecuta este script aproximadamente una vez por hora. El script recorre los tres runners pesados y el Gate. Puede limpiar un runner que está idle aunque otro esté ocupado. No elimina workspaces ni cachés de un runner con `Runner.Worker` activo.

Además, los hooks pre/post-job controlan la presión del filesystem compartido desde cada runner aislado:

- desde `RUNNER_CACHE_PRESSURE_PERCENT` (78% por defecto), vacían caches regenerables de npm/pip/nuget;
- desde `RUNNER_CACHE_EMERGENCY_PERCENT` (88% por defecto), también vacían `toolcache`;
- nunca reducen cobertura de tests ni borran workspaces activos.

## Umbrales

```env
DISK_WARN_PERCENT=75
DISK_AGGRESSIVE_PERCENT=82
DISK_EMERGENCY_PERCENT=90
DISK_RECOVERY_PERCENT=70
RUNNER_CACHE_PRESSURE_PERCENT=78
RUNNER_CACHE_EMERGENCY_PERCENT=88
```

- 75%: advertencia.
- 82%: limpieza agresiva del runner idle.
- 90%: pausa cada runner idle para proteger la VM.
- 70%: recuperación automática de runners pausados.
- 78%: los hooks de un runner pueden purgar caches regenerables antes/después del job.
- 88%: los hooks pueden purgar también `toolcache` para evitar ENOSPC durante instalación de dependencias.

Un job activo no se interrumpe automáticamente por el cleanup. El watchdog seguirá alertando si el uso es crítico.

## Actualización de imágenes

Ejecutar sólo cuando ambos runners estén idle:

```bash
./scripts/update.sh
```

El script actualiza ambos Docker-in-Docker, reconstruye una única imagen compartida del runner y reinicia el stack conservando registros y datos.

## Backup de credenciales

Normalmente es más simple volver a registrar los runners. Si se realiza una intervención y se decide respaldar las credenciales:

```bash
sudo tar czf /root/coferlandia-ci-runner-credentials.tgz \
  /srv/coferlandia-ci/runner-01/.runner \
  /srv/coferlandia-ci/runner-01/.credentials \
  /srv/coferlandia-ci/runner-01/.credentials_rsaparams \
  /srv/coferlandia-ci/runner-02/.runner \
  /srv/coferlandia-ci/runner-02/.credentials \
  /srv/coferlandia-ci/runner-02/.credentials_rsaparams
```

Este archivo contiene secretos. Protéjalo como root y elimínelo después de la intervención.

## Ampliar el filesystem

La topología actual de tres runners pesados + Gate usa 80 GiB como baseline de instalación limpia. Una instalación histórica de 45 GiB debe ampliarse si el host tiene capacidad suficiente.

Ejemplo de 45 a 80 GiB:

```bash
sudo systemctl stop coferlandia-ci-watchdog.timer coferlandia-ci-cleanup.timer
docker compose stop
sudo umount /srv/coferlandia-ci
sudo truncate -s 80G /var/lib/coferlandia-ci.img
sudo e2fsck -f /var/lib/coferlandia-ci.img
sudo resize2fs /var/lib/coferlandia-ci.img
sudo mount /srv/coferlandia-ci
docker compose up -d
sudo systemctl start coferlandia-ci-watchdog.timer coferlandia-ci-cleanup.timer
```

No reduzca un filesystem ext4 mediante `truncate`.
