# Project manifest

Version: 0.4.0

## Runtime

- `compose.yml`: tres pares aislados runner + Docker-in-Docker y un runner Gate liviano, sin puertos publicados.
- `runner/`: imagen compartida y ciclo register/run/remove.
- `hooks/`: limpieza por job segura porque cada runner tiene daemon exclusivo.
- `config/docker-daemon.json`: BuildKit, garbage collection y rotación de logs.

## Persistencia

- `runner-01` a `runner-04`: configuración y credenciales independientes.
- `work-01` a `work-04`: workspaces.
- `cache-01` a `cache-04`: package/tool caches.
- `docker-01` a `docker-03`: datos de Docker CI para los tres runners pesados.
- `certs-01` a `certs-03`: TLS interno de cada par pesado.
- `/var/lib/coferlandia-ci-watchdog`: contadores, cooldown y recuperación pendiente por runner.

## Ciclo de host

- `scripts/install-host.sh`: filesystem ext4 limitado y estructura para los cuatro runners.
- `scripts/register-runners.sh`: registro reanudable y tokens no persistentes.
- `scripts/unregister-runners.sh`: eliminación independiente de los cuatro registros.
- `scripts/status.sh`: siete servicios, tres daemons, recursos y GitHub opcional.
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
