# Uso en workflows

## Selección normal

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

GitHub selecciona cualquiera de los tres runners pesados libres. No es necesario conocer cuál ejecutará el job.

## Dos jobs simultáneos

```yaml
jobs:
  test-a:
    runs-on: [self-hosted, coferlandia-ci]
    steps:
      - run: ./scripts/test-a.sh

  test-b:
    runs-on: [self-hosted, coferlandia-ci]
    steps:
      - run: ./scripts/test-b.sh
```

Si ambos están listos al mismo tiempo, cada runner recibe uno.

## Matriz paralela

```yaml
strategy:
  max-parallel: 2
  matrix:
    shard: [1, 2]
```

Un tercer elemento de matriz quedará en cola hasta que termine uno de los dos primeros.

## Gate / agregación liviana

Los jobs que sólo consumen outputs/resultados y no ejecutan producto ni Docker deben usar la lane dedicada:

```yaml
runs-on: [self-hosted, coferlandia-ci-gate]
```

Ese listener no tiene Docker-in-Docker y no compite con los tres slots pesados.

## Docker Compose

Cada runner posee su propio daemon, pero dentro de un job sigue siendo buena práctica usar un nombre de proyecto único:

```yaml
env:
  COMPOSE_PROJECT_NAME: ci-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.job }}
```

Cerrar siempre el ambiente:

```yaml
- name: Cerrar ambiente
  if: always()
  run: docker compose down --volumes --remove-orphans
```

## Cachés

Los paquetes y toolcache se conservan por runner. Un job posterior puede caer en el otro runner y no encontrar la misma caché caliente. Esto es intencional para evitar corrupción por escrituras simultáneas.

Para caché portable entre runners, use `actions/cache` cuando sea apropiado.

## Concurrency de GitHub

La capacidad física es dos, pero cada workflow puede limitarse:

```yaml
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Timeouts

Defina límites explícitos:

```yaml
timeout-minutes: 30
```

Esto evita ocupar indefinidamente uno de los dos slots.
