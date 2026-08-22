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

## Dos registros independientes

La instalación crea:

```text
coferlandia-ci-01
coferlandia-ci-02
```

Ambos usan las mismas etiquetas y runner group, pero poseen identificadores y credenciales independientes.

Registrar:

```bash
./scripts/register-runners.sh
```

El token temporal no se guarda en `.env`. Se entrega únicamente al contenedor efímero que ejecuta `config.sh`.

## Runner groups

Para reducir el alcance:

1. crear o seleccionar un runner group;
2. autorizar sólo los repositorios necesarios;
3. configurar su nombre en `RUNNER_GROUP`;
4. registrar ambos runners en ese grupo.

## Etiquetas

Configuración predeterminada:

```env
RUNNER_LABELS=coferlandia-ci,docker
```

GitHub agrega etiquetas predeterminadas como `self-hosted`, `Linux` y `ARM64` según la plataforma.

Workflow recomendado:

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

## Permisos de workflows

Recomendación base:

```yaml
permissions:
  contents: read
```

Otorgue permisos adicionales sólo al job que los necesite.

## Repositorios públicos y forks

No permita que pull requests no confiables ejecuten código automáticamente en este servidor. Los self-hosted runners pueden acceder a recursos de la VM y comparten su kernel.

## Eliminación

Para desregistrar correctamente ambos runners:

```bash
./scripts/unregister-runners.sh
```

Elimine primero los registros remotos antes de borrar los directorios `runner-01` y `runner-02`.
