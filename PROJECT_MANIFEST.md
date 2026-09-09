# Project manifest

Version: 0.3.1

## Runtime

- `compose.yml`: dos pares aislados runner + Docker-in-Docker, sin puertos publicados.
- `runner/`: imagen compartida y ciclo register/run/remove.
- `hooks/`: limpieza por job segura porque cada runner tiene daemon exclusivo.
- `config/docker-daemon.json`: BuildKit, garbage collection y rotación de logs.

## Persistencia

- `runner-01`, `runner-02`: configuración y credenciales.
- `work-01`, `work-02`: workspaces.
- `cache-01`, `cache-02`: package/tool caches.
- `docker-01`, `docker-02`: datos de Docker CI.
- `certs-01`, `certs-02`: TLS interno.
- `/var/lib/coferlandia-ci-watchdog`: contadores, cooldown y recuperación pendiente por runner.

## Ciclo de host

- `scripts/install-host.sh`: filesystem ext4 limitado y estructura para dos instancias.
- `scripts/register-runners.sh`: registro reanudable y tokens no persistentes.
- `scripts/unregister-runners.sh`: eliminación independiente de ambos registros.
- `scripts/status.sh`: cuatro servicios, dos daemons, recursos y GitHub opcional.
- `scripts/cleanup.sh`: limpieza granular y pausa por runner.
- `scripts/watchdog.sh`: salud local/remota, alertas y self-healing seguro del listener.
- `scripts/verify-installation.sh`: validación local, broker, timers y estado remoto cuando está configurado.
- `systemd/`: timers de watchdog y cleanup.

## Documentación principal

- instalación limpia completa;
- actualización segura desde 0.2.x/0.3.x y estados mixtos;
- arquitectura y concurrencia;
- configuración GitHub;
- workflow paralelo;
- mantenimiento, monitoreo y troubleshooting;
- seguridad, redes y desinstalación.
