# Configuración de GitHub

## Alcance del registro

`RUNNER_URL` y el lugar donde se genera el token deben coincidir.

Organización:

```env
RUNNER_URL=https://github.com/coferlandia
```

Token:

```text
Organization → Settings → Actions → Runners → New self-hosted runner
```

Repositorio:

```env
RUNNER_URL=https://github.com/OWNER/REPOSITORY
```

Token:

```text
Repository → Settings → Actions → Runners → New self-hosted runner
```

Un token de repositorio utilizado con una URL de organización suele producir `404 Not Found` durante el registro.

## Cuatro registros independientes

La instalación crea:

```text
coferlandia-ci-01
coferlandia-ci-02
coferlandia-ci-03
coferlandia-ci-gate
```

Los tres primeros son runners pesados con un Docker-in-Docker exclusivo cada uno. El cuarto es un Gate liviano sin Docker-in-Docker. Los cuatro tienen identificadores y credenciales independientes y pertenecen al runner group configurado.

Registrar:

```bash
./scripts/register-runners.sh
```

El token temporal no se guarda en `.env`. Se entrega únicamente al contenedor efímero que ejecuta `config.sh`.

Este token de registro se utiliza para dar de alta un runner y es distinto de `GITHUB_TOKEN`, que GitHub crea para cada job de Actions.

## Runner groups

Para reducir el alcance:

1. crear o seleccionar un runner group;
2. autorizar sólo los repositorios necesarios;
3. configurar su nombre en `RUNNER_GROUP`;
4. registrar los cuatro runners en ese grupo.

## Etiquetas

Configuración predeterminada:

```env
RUNNER_LABELS=coferlandia-ci,docker
RUNNER_04_LABELS=coferlandia-ci-gate
```

GitHub agrega etiquetas predeterminadas como `self-hosted`, `Linux` y `ARM64` según la plataforma.

Workflow recomendado:

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

Los jobs livianos de agregación usan otra etiqueta:

```yaml
runs-on: [self-hosted, coferlandia-ci-gate]
```

## Permisos de workflows

Recomendación base:

```yaml
permissions:
  contents: read
```

Otorgue permisos adicionales sólo al job que los necesite.

## Compatibilidad de tokens de GitHub Apps (2026)

Desde el 2 de octubre de 2026, los tokens de instalación de GitHub Apps, incluidos los `GITHUB_TOKEN` de Actions, usan de forma predeterminada el formato stateless `ghs_APPID_JWT` (aproximadamente 520 caracteres). No cambian su alcance, sus permisos ni su vencimiento.

- El runner oficial gestiona la autenticación de los jobs. Los scripts de registro de Coferlandia CI no procesan el `GITHUB_TOKEN` ni analizan su formato.
- `GITHUB_MONITOR_TOKEN`, si está configurado en `/etc/coferlandia-ci-watchdog.env`, se envía como valor completo del encabezado `Authorization: Bearer` y no se valida por longitud o patrón.
- No limite el almacenamiento de tokens a 40 caracteres, no interprete el JWT y no registre los valores en logs.
- El encabezado temporal `X-GitHub-Stateless-S2S-Token` no forma parte de esta instalación; GitHub dejará de respetarlo el 30 de noviembre de 2026.

El token opcional del watchdog debe autorizar la lectura de runners del scope configurado. Si es un token de instalación de corta duración, requiere un mecanismo de renovación externo; el watchdog no lo renueva por sí mismo.

Referencias oficiales: [despliegue completo](https://github.blog/changelog/2026-10-02-stateless-github-app-installation-tokens-rolled-out/) y [concepto de `GITHUB_TOKEN`](https://docs.github.com/en/actions/concepts/security/github_token).

## Repositorios públicos y forks

No permita que pull requests no confiables ejecuten código automáticamente en este servidor. Los self-hosted runners pueden acceder a recursos de la VM y comparten su kernel.

## Eliminación

Para desregistrar correctamente los cuatro runners:

```bash
./scripts/unregister-runners.sh
```

Elimine primero los registros remotos antes de borrar cualquier directorio `runner-01` a `runner-04`. El procedimiento solicita un token de eliminación por runner y no borra el almacenamiento persistente por sí mismo.
