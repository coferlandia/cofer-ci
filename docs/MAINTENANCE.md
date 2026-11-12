# Mantenimiento y limpieza

## Estado

```bash
./scripts/status.sh
docker compose ps
docker compose logs --tail=200 runner-01 runner-02 runner-03 runner-04
```

`status.sh` informa el uso del filesystem CI y el tamaño físico/aparente de `CI_STORAGE_IMAGE`. En una imagen sparse, el tamaño aparente puede seguir siendo 80 GiB aunque el consumo físico sea mucho menor.

## Contrato de seguridad

La limpieza distingue tres estados de runner: `idle`, `busy` y `unknown`. Sólo `idle` autoriza borrados. Un error al consultar Docker, un contenedor ausente o cualquier estado ambiguo se trata como `unknown` y el ciclo se omite.

El host y los hooks pre/post-job comparten un lock por runner en `cache-XX/.cleanup.lock`. El cleanup del host toma el lease sin esperar; el pre-job puede esperar hasta `RUNNER_CLEANUP_LEASE_WAIT_SECONDS` (120 s por defecto). Esto evita que GitHub inicie un checkout mientras el host está eliminando datos regenerables.

Nunca se borran automáticamente `runner-XX`, `.runner`, `.credentials*`, certificados TLS ni el storage completo.

## Previsualización

Antes de una intervención manual:

```bash
sudo ./scripts/cleanup.sh --dry-run
```

El modo dry-run conserva todas las verificaciones y reporta los candidatos, pero no borra archivos, no ejecuta prunes destructivos, no pausa/reinicia listeners y no ejecuta `fstrim`.

## Limpieza por job

Los cuatro runners usan `TMPDIR`, `TMP` y `TEMP` en `/cache/tmp`, que pertenece al filesystem acotado de CI y no a la capa escribible del contenedor. El pre-job elimina temporales abandonados y el post-job elimina los temporales del job terminado.

Cada runner pesado ejecuta hooks sobre su Docker-in-Docker exclusivo:

- elimina contenedores residuales;
- elimina redes no usadas;
- elimina volúmenes no usados;
- conserva imágenes y build cache recientes salvo presión/presupuesto.

El Gate no ejecuta Docker-in-Docker.

## Limpieza periódica

```bash
sudo ./scripts/cleanup.sh
```

El timer ejecuta el script aproximadamente una vez por hora. Cada runner idle se procesa independientemente; un runner busy/unknown o con lease ocupado se salta sin afectar a los demás.

La política normal, incluso por debajo del umbral global de 82%, limita datos regenerables por runner:

```env
PACKAGE_CACHE_RETENTION_DAYS=7
PACKAGE_CACHE_MAX_GIB_PER_RUNNER=2
TOOLCACHE_MAX_GIB_PER_RUNNER=4
WORKSPACE_IDLE_RETENTION_HOURS=24
WORKSPACE_MAX_GIB_PER_RUNNER=4
DIND_MAX_GIB_PER_RUNNER=6
```

- npm/pip/nuget vencidos se depuran por edad; si su conjunto supera el presupuesto, se vacía mientras el runner está idle;
- `toolcache` se conserva hasta su presupuesto, salvo presión de disco;
- los workspaces/checkouts se eliminan completos cuando están vencidos o el conjunto regenerable supera el presupuesto; no se manipulan packs Git individualmente;
- un DinD que supera su presupuesto recibe reclaim agresivo de objetos no usados cuando su runner está idle.

Los valores son defaults operativos, no reservas de disco.

## Umbrales de presión

```env
DISK_WARN_PERCENT=75
DISK_AGGRESSIVE_PERCENT=82
DISK_EMERGENCY_PERCENT=90
DISK_RECOVERY_PERCENT=70
RUNNER_CACHE_PRESSURE_PERCENT=78
RUNNER_CACHE_EMERGENCY_PERCENT=88
```

- 75%: advertencia.
- 82%: reclaim agresivo de workspace/cache/DinD de runners idle.
- 90%: después de reclaim, un listener pesado idle puede pausarse para proteger la VM.
- 70%: recuperación automática de listeners pausados por disco.
- 78%: hooks pre/post-job pueden purgar npm/pip/nuget.
- 88%: hooks pueden purgar también `toolcache`.

Un job activo no se interrumpe automáticamente.

## Recuperación física del loopback

El filesystem CI vive en una imagen ext4 sparse. Borrar archivos libera espacio dentro de ext4; `fstrim` permite devolver bloques libres al filesystem host.

```env
CI_TRIM_INTERVAL_HOURS=24
```

El cleanup ejecuta trim sólo cuando:

1. `CI_STORAGE_ROOT` está montado desde el loop asociado exactamente a `CI_STORAGE_IMAGE`;
2. todos los runners están `idle`;
3. venció el intervalo;
4. `fstrim` está disponible.

El log registra bytes físicos de la imagen antes/después. El número reportado por `fstrim` no se interpreta como espacio físico recuperado.

## Actualización de imágenes

Ejecutar sólo cuando los cuatro runners estén idle:

```bash
./scripts/update.sh
```

Después de cambios en la imagen del runner, usar `docker compose up -d --build` y verificar los siete servicios. Consulte [UPGRADE.md](UPGRADE.md).

## Backup de credenciales

Normalmente es más simple volver a registrar los runners. Si una intervención requiere respaldar credenciales:

```bash
files=()
for index in 01 02 03 04; do
  for filename in .runner .credentials .credentials_rsaparams; do
    files+=("/srv/coferlandia-ci/runner-${index}/${filename}")
  done
done
sudo install -m 0600 /dev/null /root/coferlandia-ci-runner-credentials.tgz
sudo tar czf /root/coferlandia-ci-runner-credentials.tgz "${files[@]}"
sudo chmod 0600 /root/coferlandia-ci-runner-credentials.tgz
```

Este archivo contiene secretos. Protéjalo como root y elimínelo después de la intervención.

## Ampliar el filesystem

La topología de tres runners pesados + Gate usa 80 GiB como baseline de instalación limpia. Para instalaciones históricas consulte [UPGRADE.md](UPGRADE.md). Nunca reduzca un filesystem ext4 mediante `truncate`.
