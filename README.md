# Coferlandia CI Runner

Servidor self-hosted de GitHub Actions para ejecutar hasta **dos jobs concurrentes** en una VM compartida, sin exponer el Docker productivo del host.

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
    ├── filesystem limitado /srv/coferlandia-ci
    └── systemd
        ├── watchdog cada 5 minutos
        └── cleanup diario
```

Cada listener acepta un job. GitHub puede ejecutar dos jobs simultáneos, uno en cada runner. Cada runner posee:

- credenciales independientes;
- workspace independiente;
- cachés independientes;
- daemon Docker-in-Docker independiente;
- red Docker interna independiente.

La separación de los daemons es deliberada. Los hooks pueden eliminar contenedores, redes y volúmenes al terminar un job sin afectar el job concurrente del otro runner.

## Controles principales

- Ningún workflow recibe `/var/run/docker.sock` del host.
- No se publica ningún puerto nuevo.
- Los dos Docker CI se comunican únicamente por TLS dentro de sus redes privadas.
- CPU, memoria, PIDs, logs y almacenamiento tienen límites.
- El filesystem de CI tiene tamaño máximo configurable.
- Watchdog y limpieza corren fuera de los runners.
- El stack puede seguir funcionando con un runner ocupado y otro disponible.
- El watchdog puede distinguir un listener localmente sano de un runner remotamente `offline` y aplicar self-healing seguro cuando el monitoreo GitHub está configurado.

## Instalación limpia

La guía principal es:

- [Manual de instalación limpia](docs/CLEAN_INSTALL.md)

Resumen en la VM:

```bash
cd ~/docker-projects
unzip ~/uploads/coferlandia-ci-runner-0.3.1.zip
cd coferlandia-ci-runner

cp .env.example .env
nano .env

./scripts/check-prerequisites.sh
./scripts/host-survey.sh before
sudo ./scripts/install-host.sh
./scripts/register-runners.sh
sudo ./scripts/install-systemd.sh
sudo ./scripts/verify-installation.sh
./scripts/host-survey.sh after-idle
```

## Actualización

Para actualizar una instalación existente, especialmente desde 0.2.x o desde un estado mixto de archivos 0.2.x con contenedores 0.3.x, siga:

- [Actualización segura](docs/UPGRADE.md)

No ejecute Compose desde un directorio antiguo si sus servicios no coinciden con la topología activa.

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

Cuando dos jobs compatibles están en cola, GitHub asigna uno a `coferlandia-ci-01` y otro a `coferlandia-ci-02`. Un tercer job permanece en cola hasta que alguno quede libre.

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

Un workflow puede ejecutar código arbitrario. El aislamiento evita que los jobs controlen el Docker productivo, pero los dos Docker-in-Docker siguen compartiendo el kernel de la VM. Utilice este servidor únicamente con repositorios y workflows confiables.
