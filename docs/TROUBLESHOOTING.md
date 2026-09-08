# Resolución de problemas

## Estado general

```bash
sudo ./scripts/status.sh
docker compose ps
df -h / /srv/coferlandia-ci
```

## Un runner aparece offline

Primero compare salud local con estado remoto:

```bash
gh api /orgs/coferlandia/actions/runners \
  --jq '.runners[] | select(.name | startswith("coferlandia-ci")) | "\(.name) status=\(.status) busy=\(.busy) labels=\([.labels[].name] | join(","))"'
```

Un contenedor puede aparecer `healthy` porque `Runner.Listener` está vivo y, aun así, GitHub puede reportarlo `offline`.

Logs:

```bash
docker compose logs --tail=300 runner-01
docker compose logs --tail=300 runner-02
```

Diagnóstico local:

```bash
sudo ls -lah /srv/coferlandia-ci/runner-01/_diag
sudo ls -lah /srv/coferlandia-ci/runner-02/_diag
```

Si aparece un timeout como:

```text
POST request to https://broker.actions.githubusercontent.com/session timed out
```

compruebe desde el runner:

```bash
docker compose exec -T runner-01 \
  curl -fsS --max-time 15 https://broker.actions.githubusercontent.com/health
```

La respuesta del `/health` confirma DNS/TCP/TLS y acceso HTTP al broker, pero no garantiza que la creación de sesión del listener esté funcionando.

### Self-healing

Con `GITHUB_MONITOR_TOKEN` configurado, el watchdog confirma el estado `offline` durante la cantidad de ciclos configurada y puede reiniciar únicamente el listener afectado. Consulte:

```bash
sudo journalctl -u coferlandia-ci-watchdog.service -n 100 --no-pager
```

Si el self-healing no está configurado o se requiere recuperación manual:

```bash
docker compose restart runner-01
# o
docker compose restart runner-02
```

No reinicie su Docker-in-Docker si el daemon está sano y el problema está limitado a la sesión GitHub del listener.

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

- que al menos un runner esté `online` e `idle` en GitHub, no sólo `healthy` en Docker;
- que `runs-on` incluya `coferlandia-ci`;
- que el runner group permita el repositorio;
- que los dos slots no estén ocupados.

Un tercer job en cola es comportamiento normal.

Si todos los jobs compatibles quedan `queued` y ambos contenedores locales están `healthy`, consulte explícitamente la API de runners. Si ambos aparecen `offline`, el problema está en la disponibilidad remota de los listeners y no en las labels del workflow.

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

## El directorio operativo no coincide con los contenedores

Si `docker compose config --services` muestra `runner` y `docker-ci`, pero `docker inspect` indica que los contenedores activos pertenecen a `runner-01`/`runner-02`, no use ese Compose antiguo. Siga [UPGRADE.md](UPGRADE.md) para normalizar el despliegue sin borrar `/srv/coferlandia-ci`.

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
