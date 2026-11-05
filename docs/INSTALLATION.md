# Instalación

La instalación soportada para el código 0.4.0 comprende tres runners pesados con Docker CI aislado y un cuarto runner Gate sin Docker-in-Docker.

Siga el procedimiento completo en:

- [CLEAN_INSTALL.md](CLEAN_INSTALL.md)

Secuencia esencial:

```bash
cp .env.example .env
nano .env
./scripts/check-prerequisites.sh
./scripts/host-survey.sh before
sudo ./scripts/install-host.sh
./scripts/register-runners.sh
sudo ./scripts/install-systemd.sh
./scripts/verify-installation.sh
./scripts/host-survey.sh after-idle
```

No copie credenciales ni directorios `runner-*` desde otra máquina. Cada runner debe registrarse desde la VM destino mediante un token temporal de GitHub.
