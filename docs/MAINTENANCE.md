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

## Limpieza diaria

```bash
sudo ./scripts/cleanup.sh
```

El script recorre ambos pares. Puede limpiar el runner que está idle aunque el otro esté ocupado. No elimina el workspace ni las cachés de un runner con `Runner.Worker` activo.

## Umbrales

```env
DISK_WARN_PERCENT=75
DISK_AGGRESSIVE_PERCENT=82
DISK_EMERGENCY_PERCENT=90
DISK_RECOVERY_PERCENT=70
```

- 75%: advertencia.
- 82%: limpieza agresiva del runner idle.
- 90%: pausa cada runner idle para proteger la VM.
- 70%: recuperación automática de runners pausados.

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

Ejemplo de 30 a 40 GiB:

```bash
sudo systemctl stop coferlandia-ci-watchdog.timer coferlandia-ci-cleanup.timer
docker compose stop
sudo umount /srv/coferlandia-ci
sudo truncate -s 40G /var/lib/coferlandia-ci.img
sudo e2fsck -f /var/lib/coferlandia-ci.img
sudo resize2fs /var/lib/coferlandia-ci.img
sudo mount /srv/coferlandia-ci
docker compose up -d
sudo systemctl start coferlandia-ci-watchdog.timer coferlandia-ci-cleanup.timer
```

No reduzca un filesystem ext4 mediante `truncate`.
