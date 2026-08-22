# Resolución de problemas

## Estado general

```bash
./scripts/status.sh
docker compose ps
df -h / /srv/coferlandia-ci
```

## Un runner aparece offline

```bash
docker compose logs --tail=300 runner-01
docker compose logs --tail=300 runner-02
```

Diagnóstico local:

```bash
sudo ls -lah /srv/coferlandia-ci/runner-01/_diag
sudo ls -lah /srv/coferlandia-ci/runner-02/_diag
```

Reiniciar sólo la instancia afectada:

```bash
docker compose restart runner-01
# o
docker compose restart runner-02
```

## Un Docker CI está unhealthy

```bash
docker compose logs --tail=300 docker-ci-01
docker compose exec docker-ci-01 docker info
```

Para la segunda instancia, reemplazar `01` por `02`.

Reinicio controlado de un par:

```bash
docker compose restart docker-ci-01
sleep 15
docker compose restart runner-01
```

## Registro devuelve 404

Verifique que el token y `RUNNER_URL` tengan el mismo alcance:

- token de organización con URL de organización;
- token de repositorio con URL de repositorio.

Genere un token nuevo y ejecute otra vez:

```bash
./scripts/register-runners.sh
```

El script conserva el runner que ya haya quedado registrado y continúa con el faltante.

## Un job queda queued

Compruebe:

- que al menos un runner esté `online` e `idle`;
- que `runs-on` incluya `coferlandia-ci`;
- que el runner group permita el repositorio;
- que los dos slots no estén ocupados.

Un tercer job en cola es comportamiento normal.

## Error de permisos

```bash
sudo chown -R 1001:123 \
  /srv/coferlandia-ci/runner-01 \
  /srv/coferlandia-ci/work-01 \
  /srv/coferlandia-ci/cache-01 \
  /srv/coferlandia-ci/runner-02 \
  /srv/coferlandia-ci/work-02 \
  /srv/coferlandia-ci/cache-02
```

## No space left on device

```bash
sudo ./scripts/cleanup.sh
df -h /srv/coferlandia-ci
sudo du -xh --max-depth=2 /srv/coferlandia-ci | sort -h
```

Marcadores de pausa:

```text
/srv/coferlandia-ci/.runner-01-paused-disk
/srv/coferlandia-ci/.runner-02-paused-disk
```

Después de liberar espacio, el cleanup reinicia las instancias cuando el uso baja del umbral de recuperación.

## Reset de una sola instancia

Si únicamente el runner 2 está corrupto:

1. eliminar `coferlandia-ci-02` desde GitHub;
2. detener `runner-02`;
3. eliminar solamente `/srv/coferlandia-ci/runner-02`;
4. recrear el directorio con UID/GID `1001:123`;
5. ejecutar `./scripts/register-runners.sh`.

No borre los datos del runner sano.

## Tini warning durante registro

El contenedor efímero puede advertir que Tini no es PID 1 al usar `docker compose run`. Si el proceso continúa hasta `Runner successfully added`, el warning no invalida el registro.
