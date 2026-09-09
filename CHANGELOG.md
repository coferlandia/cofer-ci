# Changelog

## 0.3.1 - 2026-09-08

- Self-healing seguro para runners que permanezcan `offline` en GitHub mientras el listener local siga activo.
- Debounce configurable antes del restart y cooldown por runner para evitar ciclos de reinicio.
- Un único intento automático por incidente hasta que GitHub vuelva a reportar el runner `online`.
- Persistencia de estado por runner bajo `/var/lib/coferlandia-ci-watchdog`.
- Verificación integral ampliada con estado remoto de GitHub, broker de Actions y timers systemd.
- Documentación de upgrade desde 0.2.x, 0.3.0 y estados mixtos, preservando `/srv/coferlandia-ci`.
- Documentación de la diferencia entre health local del contenedor y disponibilidad remota del runner.

## 0.3.0 - 2026-08-04

- Capacidad para dos jobs concurrentes mediante dos runners independientes.
- Dos Docker-in-Docker aislados para impedir interferencia entre jobs simultáneos.
- Credenciales, workspaces, cachés, certificados y almacenamiento Docker separados.
- Registro y desregistro reanudables de ambos runners.
- Watchdog, status, verificación y limpieza adaptados a cuatro servicios.
- Limpieza granular: un runner idle puede limpiarse aunque el otro esté ocupado.
- Pausa y recuperación por presión de disco por runner.
- Smoke test paralelo con matriz de dos jobs.
- Manual completo de instalación limpia.
- Documentación de arquitectura, concurrencia, seguridad, operación y desinstalación.

## 0.2.0 - 2026-08-02

- Guía completa para conexión SSH desde Windows/Git Bash.
- Transferencia del ZIP y checksum mediante `scp`.
- Convención de carpetas independientes bajo `~/docker-projects`.
- Relevamiento automatizado de la VM antes, durante y después de instalar CI.
- Informes humanos y métricas comparables de CPU, memoria, discos, Docker, procesos y puertos.

## 0.1.0 - 2026-08-02

- Primera versión instalable con un runner y un Docker CI aislado.
- Límites de CPU, RAM, PIDs, logs y filesystem.
- Limpieza, watchdog, Telegram y documentación operativa.
