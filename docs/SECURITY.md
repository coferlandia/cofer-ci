# Seguridad

## Modelo de confianza

Los workflows ejecutan comandos arbitrarios. Esta solución separa Docker CI del Docker productivo y separa los dos jobs concurrentes entre sí, pero no transforma la VM compartida en una frontera frente a código hostil.

Use los runners sólo con repositorios y workflows confiables.

## Controles implementados

- dos daemons Docker CI independientes;
- ninguna montura de `/var/run/docker.sock` del host;
- TLS interno runner↔Docker CI;
- redes separadas por runner;
- ningún puerto publicado;
- runner sin privilegios y `no-new-privileges`;
- límites de CPU, memoria, PIDs y logs;
- filesystem con techo de capacidad;
- credenciales separadas;
- workspaces y cachés separados;
- watchdog y cleanup externos.

## Riesgo de Docker-in-Docker

Cada daemon usa `privileged: true` y comparte el kernel de la VM. El aislamiento protege principalmente al Docker productivo y evita interferencia accidental entre jobs, pero no es equivalente a una VM por job.

## GitHub

- restringir el runner group a repositorios seleccionados;
- no ejecutar PR de forks públicos automáticamente;
- revisar cambios en `.github/workflows`;
- usar `permissions: contents: read` por defecto;
- proteger environments y secrets productivos;
- usar aprobación manual para deployments.

## Secretos

No almacenar en `.env`:

- PAT permanentes;
- token de Telegram;
- claves SSH personales;
- secretos productivos.

El monitoreo utiliza:

```text
/etc/coferlandia-ci-watchdog.env
```

con permisos `0600`.
