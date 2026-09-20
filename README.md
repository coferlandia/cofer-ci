# Coferlandia CI Runner

Servidor self-hosted de GitHub Actions para ejecutar hasta **tres jobs concurrentes** en una VM compartida, sin exponer el Docker productivo del host.

Versión: **0.3.1**

## Arquitectura

```text
GitHub Actions
        │ HTTPS saliente
        ▼
VM Coferlandia
├── stack productivo existente
└── Coferlandia CI
    ├── runner-01 ──TLS── docker-ci-01
    ├── runner-02 ──TLS── docker-ci-02
    ├── runner-03 ──TLS── docker-ci-03
    ├── filesystem limitado /srv/coferlandia-ci
    └── systemd
        ├── watchdog cada 5 minutos
        └── cleanup diario
```

Cada listener acepta un job. GitHub puede ejecutar tres jobs simultáneos, uno en cada runner. Cada runner posee credenciales, workspace, cachés, daemon Docker-in-Docker y red Docker interna independientes.

La separación de los daemons es deliberada. Los hooks pueden eliminar contenedores, redes y volúmenes al terminar un job sin afectar los jobs concurrentes de los otros runners.

## Controles principales

- Ningún workflow recibe `/var/run/docker.sock` del host.
- No se publica ningún puerto nuevo.
- Los tres Docker CI se comunican únicamente por TLS dentro de sus redes privadas.
- CPU, memoria, PIDs, logs y almacenamiento tienen límites.
- El filesystem de CI tiene tamaño máximo configurable.
- Watchdog y limpieza corren fuera de los runners.
- El stack puede seguir funcionando mientras quede al menos un runner disponible.
- El watchdog puede distinguir un listener localmente sano de un runner remotamente `offline` y aplicar self-healing seguro cuando el monitoreo GitHub está configurado.

## Instalación y actualización

La instalación limpia está documentada en [docs/CLEAN_INSTALL.md](docs/CLEAN_INSTALL.md) y la actualización de una instalación existente en [docs/UPGRADE.md](docs/UPGRADE.md).

Antes de habilitar tres jobs pesados simultáneos en una VM compartida, validar capacidad real del host. Con los límites predeterminados, los máximos agregados alcanzan aproximadamente 5,25 CPU y 27 GiB de memoria; son límites, no reservas.

## Operación habitual

```bash
sudo ./scripts/status.sh
./scripts/start.sh
./scripts/stop.sh
./scripts/restart.sh
docker compose logs --tail=200 -f
sudo ./scripts/cleanup.sh
```

## Concurrencia

Los workflows no necesitan elegir un runner específico:

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

Cuando tres jobs compatibles están en cola, GitHub puede asignarlos a `coferlandia-ci-01`, `coferlandia-ci-02` y `coferlandia-ci-03`. Un cuarto job permanece en cola hasta que alguno quede libre.

## Documentación

- [Instalación limpia](docs/CLEAN_INSTALL.md)
- [Actualización segura](docs/UPGRADE.md)
- [Arquitectura y concurrencia](docs/ARCHITECTURE.md)
- [Instalación de referencia](docs/INSTALLATION.md)
- [Conexión y transferencia desde Windows/Git Bash](docs/VM_DEPLOYMENT.md)
- [Configuración de GitHub](docs/GITHUB_CONFIGURATION.md)
- [Uso en workflows](docs/WORKFLOW_USAGE.md)
- [Mantenimiento y limpieza](docs/MAINTENANCE.md)
- [Monitoreo y Telegram](docs/MONITORING.md)
- [Redes y puertos](docs/NETWORKING.md)
- [Seguridad](docs/SECURITY.md)
- [Relevamientos de la VM](docs/HOST_SURVEY.md)
- [Resolución de problemas](docs/TROUBLESHOOTING.md)
- [Desinstalación completa](docs/UNINSTALLATION.md)

## Alcance de confianza

Un workflow puede ejecutar código arbitrario. El aislamiento evita que los jobs controlen el Docker productivo, pero los tres Docker-in-Docker siguen compartiendo el kernel de la VM. Utilice este servidor únicamente con repositorios y workflows confiables.
