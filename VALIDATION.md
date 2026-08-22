# Validación del paquete 0.3.0

Fecha de empaquetado: 2026-08-04

## Comprobaciones realizadas

- sintaxis Bash de todos los scripts, hooks y entrypoint;
- parseo YAML de `compose.yml` y workflows de ejemplo;
- parseo JSON de `config/docker-daemon.json`;
- existencia de los cuatro servicios esperados;
- separación de redes, workspaces, cachés, credenciales y Docker CI;
- ausencia de `ports:` publicados;
- enlaces Markdown relativos;
- ausencia de `.env`, tokens reales, credenciales y reportes privados;
- helpers de nombres y rutas para los índices `01` y `02`;
- estructura y permisos ejecutables del paquete.

## Invariantes verificadas

- `runner-01` sólo utiliza `docker-ci-01`;
- `runner-02` sólo utiliza `docker-ci-02`;
- cada par utiliza una red distinta;
- cada runner utiliza directorios persistentes distintos;
- los hooks globales de Docker son seguros porque actúan sobre daemons separados;
- el watchdog y el cleanup recorren las dos instancias;
- la verificación exige que ambos runners estén registrados y healthy.

## Validación pendiente en la VM destino

El entorno de empaquetado no dispone de Docker Engine. Deben ejecutarse en la VM:

```bash
cp .env.example .env
docker compose config
./scripts/check-prerequisites.sh
sudo ./scripts/install-host.sh
./scripts/register-runners.sh
./scripts/verify-installation.sh
```

La validación funcional final es `examples/workflows/runner-smoke-test.yml`, que ejecuta dos jobs simultáneos.
