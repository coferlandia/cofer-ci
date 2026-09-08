# Validación del paquete 0.3.1

Fecha: 2026-09-08

## Validación automatizada en PR

El repositorio ejecuta `.github/workflows/validate.yml` sobre GitHub-hosted `ubuntu-latest`, sin depender de los self-hosted runners administrados por este proyecto.

El job ejecuta:

```bash
./scripts/validate-package.sh
```

Ese validador comprueba:

- sintaxis Bash de todos los scripts, hooks y entrypoint;
- parseo JSON de `config/docker-daemon.json`;
- parseo de Docker Compose usando `.env.example`;
- ausencia de `ports:` publicados;
- existencia de `runner-01`, `runner-02`, `docker-ci-01` y `docker-ci-02`;
- presencia de los parámetros de self-healing en `monitoring.env.example`;
- existencia de la documentación operativa principal, incluida la guía de upgrade.

## Invariantes revisadas para 0.3.1

- la salud local del contenedor y el estado remoto del runner son controles separados;
- el self-healing sólo actúa después de chequeos `offline` consecutivos configurables;
- sólo se reinicia el listener afectado, nunca su Docker-in-Docker por un incidente exclusivamente remoto;
- no se reinicia un runner que tenga `Runner.Worker` activo;
- después de un restart automático queda una recuperación pendiente y no se repiten reinicios mientras el runner continúe `offline`;
- un incidente futuro respeta `RUNNER_RESTART_COOLDOWN_SECONDS`;
- el estado de cada runner se persiste en `/var/lib/coferlandia-ci-watchdog`;
- una falla de la API de GitHub genera incidencia pero no dispara restart;
- `verify-installation.sh` puede verificar broker, timers y estado remoto cuando el token de monitoreo está disponible;
- el upgrade preserva `/srv/coferlandia-ci` y distingue instalación 0.2.x pura, 0.3.x y estado mixto.

## Validación pendiente en la VM destino

La prueba funcional final requiere la VM porque involucra los registros existentes, systemd, `/srv/coferlandia-ci` y el estado remoto real en GitHub.

Después del merge y despliegue ejecutar:

```bash
cd ~/docker-projects/coferlandia-ci-runner
sudo ./scripts/status.sh
sudo ./scripts/verify-installation.sh
```

Confirmar además:

```bash
gh api /orgs/coferlandia/actions/runners \
  --jq '.runners[] | select(.name | startswith("coferlandia-ci")) | "\(.name) status=\(.status) busy=\(.busy)"'
```

Luego realizar el smoke test paralelo y un reboot completo:

```bash
sudo reboot
```

Al volver, ambos runners deben quedar `online/Idle` sin re-registro manual.

La simulación destructiva de un runner `offline` no se realiza automáticamente en CI para evitar afectar capacidad real; la recuperación se valida en la VM mediante el watchdog, logs y estado remoto documentados en `docs/MONITORING.md` y `docs/TROUBLESHOOTING.md`.
