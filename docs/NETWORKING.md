# Redes y puertos

## Sin puertos entrantes nuevos

`compose.yml` no contiene `ports:`. Los puertos 2376 se declaran sólo con `expose` y existen dentro de redes Docker privadas.

| Flujo | Puerto | Exposición |
|---|---:|---|
| Administrador → VM | 22 | SSH ya existente |
| runners → GitHub | 443 | saliente |
| runners → registries/paquetes | 443 | saliente |
| watchdog → Telegram | 443 | saliente |
| runner-01 → docker-ci-01 | 2376 | red interna 01, TLS |
| runner-02 → docker-ci-02 | 2376 | red interna 02, TLS |
| Internet → runners | ninguno | no requerido |

No habilite 2376 en UFW, OCI Security Lists, Network Security Groups ni proxy reverso.

## Verificación

```bash
docker compose ps
sudo ss -lntp
```

No debe aparecer `0.0.0.0:2376` ni `[::]:2376`.

Salida desde cada runner:

```bash
docker compose exec runner-01 curl -I https://api.github.com
docker compose exec runner-02 curl -I https://api.github.com
```
