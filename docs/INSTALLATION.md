# Instalación

La instalación soportada para la versión 0.3.0 es una instalación limpia de dos runners.

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
