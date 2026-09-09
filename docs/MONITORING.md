# Monitoreo

## Watchdog

El timer ejecuta cada cinco minutos:

```bash
sudo systemctl status coferlandia-ci-watchdog.timer --no-pager
```

Comprueba:

- Docker del host;
- `runner-01` y `runner-02`;
- `docker-ci-01` y `docker-ci-02`;
- healthchecks y reinicios;
- respuesta de ambos Docker CI;
- filesystem raíz;
- filesystem CI;
- estado remoto opcional de ambos runners.

La salud local y la disponibilidad remota son controles distintos. Un contenedor puede estar `healthy` porque `Runner.Listener` está vivo y, al mismo tiempo, GitHub puede reportar ese runner como `offline`. El watchdog usa el estado remoto para detectar ese caso.

## Configuración

```bash
sudo nano /etc/coferlandia-ci-watchdog.env
sudo chmod 600 /etc/coferlandia-ci-watchdog.env
```

Telegram:

```env
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

GitHub:

```env
GITHUB_MONITOR_TOKEN=
GITHUB_SCOPE_TYPE=org
GITHUB_OWNER=coferlandia
GITHUB_REPOSITORY=
```

Los nombres remotos se toman de `.env`.

Para que el watchdog pueda detectar y recuperar un runner remotamente `offline`, `GITHUB_MONITOR_TOKEN` debe permitir consultar los self-hosted runners del scope configurado.

## Self-healing de listeners

Valores por defecto:

```env
RUNNER_OFFLINE_CHECKS_BEFORE_RESTART=2
RUNNER_RESTART_COOLDOWN_SECONDS=1800
```

La política es deliberadamente conservadora:

1. un primer chequeo `offline` sólo incrementa el contador del runner;
2. al alcanzar la cantidad configurada de chequeos consecutivos, el watchdog verifica que el contenedor esté `running`, `healthy` y sin `Runner.Worker` activo;
3. si cumple esas condiciones, reinicia únicamente `runner-01` o `runner-02` según corresponda;
4. nunca reinicia `docker-ci-01` o `docker-ci-02` por un problema exclusivamente remoto del listener;
5. después de un reinicio automático queda una recuperación pendiente; mientras el runner siga `offline` no se realizan reinicios repetidos;
6. cuando GitHub vuelve a reportarlo `online`, se limpia el incidente y queda habilitada una futura recuperación, respetando el cooldown.

El estado por runner se persiste bajo `/var/lib/coferlandia-ci-watchdog/`, por lo que un nuevo ciclo del timer conserva contadores, cooldown y recuperaciones pendientes.

## Pruebas

```bash
sudo ./scripts/test-telegram.sh
sudo systemctl start coferlandia-ci-watchdog.service
sudo systemctl status coferlandia-ci-watchdog.service --no-pager
sudo journalctl -u coferlandia-ci-watchdog.service -n 100 --no-pager
```

## Estado interactivo

Para incluir el archivo de monitoreo protegido con `chmod 600`, ejecute:

```bash
sudo ./scripts/status.sh
```

Muestra los cuatro contenedores, recursos, disco, almacenamiento interno de cada daemon y, si `GITHUB_MONITOR_TOKEN` está configurado, el estado remoto de ambos runners.
