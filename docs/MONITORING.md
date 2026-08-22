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

GitHub opcional:

```env
GITHUB_MONITOR_TOKEN=
GITHUB_SCOPE_TYPE=org
GITHUB_OWNER=coferlandia
GITHUB_REPOSITORY=
```

Los nombres remotos se toman de `.env`.

## Pruebas

```bash
sudo ./scripts/test-telegram.sh
sudo systemctl start coferlandia-ci-watchdog.service
sudo journalctl -u coferlandia-ci-watchdog.service -n 100 --no-pager
```

## Estado interactivo

```bash
./scripts/status.sh
```

Muestra los cuatro contenedores, recursos, disco y el almacenamiento interno de cada daemon.
