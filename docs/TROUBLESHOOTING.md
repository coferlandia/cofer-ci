# Resolución de problemas

## Estado general

```bash
sudo ./scripts/status.sh
docker compose ps
df -h / /srv/coferlandia-ci
```

## Un job termina con exit 137 o aparece `Killed`

`137` normalmente significa que el proceso recibió `SIGKILL`. En estos runners, si una suite muestra todos sus tests aprobados y luego aparece `Killed`, primero descarte un OOM del cgroup antes de investigar el código de la aplicación.

Busque evidencia del kernel en la ventana exacta del fallo:

```bash
sudo journalctl -k --utc \
  --since "YYYY-MM-DD HH:MM:SS" \
  --until "YYYY-MM-DD HH:MM:SS" \
  | grep -Ei 'oom|out of memory|killed process|memory cgroup|memory limit'
```

Revise además el límite y los contadores del runner afectado:

```bash
docker inspect coferlandia-ci-runner-01 \
  --format 'memory={{.HostConfig.Memory}} memory_swap={{.HostConfig.MemorySwap}} state_oom_killed={{.State.OOMKilled}}'

docker exec coferlandia-ci-runner-01 sh -lc '
  echo -n "memory.max="; cat /sys/fs/cgroup/memory.max
  echo -n "memory.current="; cat /sys/fs/cgroup/memory.current
  echo -n "memory.peak="; cat /sys/fs/cgroup/memory.peak
  cat /sys/fs/cgroup/memory.events
'
```

Si `memory.events` muestra `oom_kill 1` o más, o el kernel informa `Memory cgroup out of memory`, el límite del contenedor fue alcanzado aunque `free -h` muestre memoria disponible en el host. No trate ese caso como un test fallido.

La línea base actual usa `RUNNER_MEMORY=5g` para los tres runners pesados. Después de modificar `.env`, espere a que los jobs terminen, valide y recree sólo los listeners pesados:

```bash
docker compose config | grep -A8 -B2 'mem_limit'
docker compose up -d --force-recreate runner-01 runner-02 runner-03
```

Confirme que los tres vuelvan a `healthy` y que `memory.max` refleje el nuevo límite antes de reejecutar el workflow. El Gate tiene su propio límite (`GATE_RUNNER_MEMORY`).

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
docker compose logs --tail=300 runner-03
docker compose logs --tail=300 runner-04
```

Diagnóstico local:

```bash
sudo ls -lah /srv/coferlandia-ci/runner-01/_diag
sudo ls -lah /srv/coferlandia-ci/runner-02/_diag
sudo ls -lah /srv/coferlandia-ci/runner-03/_diag
sudo ls -lah /srv/coferlandia-ci/runner-04/_diag
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
# o runner-03 / runner-04, sólo el listener afectado
```

No reinicie su Docker-in-Docker si el daemon está sano y el problema está limitado a la sesión GitHub del listener.

## Un Docker CI está unhealthy

```bash
docker compose logs --tail=300 docker-ci-01
docker compose exec docker-ci-01 docker info
```

Para las demás instancias pesadas, reemplazar `01` por `02` o `03`. El Gate (`runner-04`) no tiene Docker CI.

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
- que los tres slots pesados no estén ocupados, o el Gate si el job usa `coferlandia-ci-gate`.

Un cuarto job pesado en cola es comportamiento normal. Un job Gate usa su listener exclusivo y no compite por los tres slots pesados.

Si todos los jobs compatibles quedan `queued` y los contenedores locales están `healthy`, consulte explícitamente la API de runners. Si GitHub los reporta `offline`, el problema está en la disponibilidad remota de los listeners y no necesariamente en las etiquetas del workflow.

## Error de permisos

```bash
for index in 01 02 03 04; do
  sudo chown -R 1001:123 \
    "/srv/coferlandia-ci/runner-${index}" \
    "/srv/coferlandia-ci/work-${index}" \
    "/srv/coferlandia-ci/cache-${index}"
done
```

## No space left on device

Primero mida tanto el filesystem acotado como la asignación física de la imagen sparse:

```bash
sudo ./scripts/status.sh
df -h / /srv/coferlandia-ci
du -h /var/lib/coferlandia-ci.img
du -h --apparent-size /var/lib/coferlandia-ci.img
```

Previsualice antes de borrar:

```bash
sudo ./scripts/cleanup.sh --dry-run
```

Si el plan es razonable, ejecute:

```bash
sudo ./scripts/cleanup.sh
```

El cleanup sólo toca runners confirmados `idle`; `busy`, `unknown` o un lease ocupado se omiten. No elimine manualmente `runner-XX`, certificados ni el directorio completo de CI para resolver presión de disco.

Para localizar crecimiento residual:

```bash
sudo du -xh --max-depth=2 /srv/coferlandia-ci | sort -h | tail -80
docker ps --size
```

Los checkouts Git muy grandes se recuperan eliminando el workspace regenerable completo cuando el runner está idle; no borre `.git/objects/pack` selectivamente.

Marcadores de pausa:

```text
/srv/coferlandia-ci/.runner-01-paused-disk
/srv/coferlandia-ci/.runner-02-paused-disk
/srv/coferlandia-ci/.runner-03-paused-disk
```

Después de liberar espacio, el cleanup reinicia los runners pesados pausados cuando el uso baja del umbral de recuperación. El Gate no utiliza este mecanismo. El trim periódico sólo devuelve bloques físicos cuando el mount loop está verificado y todos los runners están idle.

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
