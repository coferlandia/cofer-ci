# Changelog

## Unreleased

- Agregada lane `coferlandia-ci-gate` con un cuarto runner liviano sin Docker-in-Docker para jobs de agregación/control-plane.
- Separado el Gate de Fast CI de los tres runners pesados para que no compita con PostgreSQL/FULL.
- Extendidos provisión, registro, status, watchdog y verificación para la topología 3+1.

- Aumentado el límite predeterminado de cada runner de 3 GiB a 5 GiB después de confirmar un OOM de cgroup durante una validación completa de SecretarIA: los 2270 tests backend habían terminado correctamente, pero `pytest` fue finalizado con `SIGKILL`/exit 137 antes de cerrar el proceso.
- Alineada la configuración predeterminada de los Docker-in-Docker con la instalación operativa validada: 4 GiB de memoria, 1024 PIDs y 512 MiB de `shm` por daemon.
- Actualizada la documentación de dimensionamiento, instalación y diagnóstico de OOM para que una instalación limpia reproduzca la línea base operativa actual.

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
