# Arquitectura y concurrencia

## Objetivo

La topología actual permite ejecutar tres jobs pesados simultáneos y un Gate liviano independiente sin permitir que un job interfiera con el ambiente Docker de los otros ni con los contenedores productivos del host.

## Componentes

| Componente | Función | Estado persistente |
|---|---|---|
| `runner-01` | Listener GitHub Actions 1 | `runner-01`, `work-01`, `cache-01` |
| `docker-ci-01` | Docker exclusivo del runner 1 | `docker-01`, `certs-01` |
| `runner-02` | Listener GitHub Actions 2 | `runner-02`, `work-02`, `cache-02` |
| `docker-ci-02` | Docker exclusivo del runner 2 | `docker-02`, `certs-02` |
| `runner-03` | Listener GitHub Actions 3 | `runner-03`, `work-03`, `cache-03` |
| `docker-ci-03` | Docker exclusivo del runner 3 | `docker-03`, `certs-03` |
| `runner-04` | Listener liviano exclusivo para Gate/agregación | `runner-04`, `work-04`, `cache-04` |
| filesystem CI | Techo de almacenamiento común | `/srv/coferlandia-ci` |
| watchdog | Salud, disco y alertas | systemd/journald |
| cleanup | Retención y recuperación | systemd/journald |

## Por qué no se comparte un único Docker CI

Los workflows pueden ejecutar comandos como:

```bash
docker compose down --volumes
docker container prune
docker network prune
docker volume prune
```

Además, los hooks defensivos eliminan recursos residuales antes y después de cada job. En un daemon compartido, un job podría borrar contenedores, redes o volúmenes utilizados por otro.

Docker Engine no ofrece namespaces independientes por cliente. Por ese motivo, la frontera segura y simple es un daemon por runner.

## Concurrencia efectiva

- Cada `Runner.Listener` ejecuta un solo job.
- Existen tres listeners pesados y un listener Gate liviano.
- Capacidad pesada máxima: tres jobs simultáneos.
- Un cuarto job pesado queda en cola; el Gate puede correr en paralelo en `runner-04`.
- Dentro de cada job pueden ejecutarse múltiples procesos y contenedores.

## Aislamiento

```text
runner-01 → red-01 → docker-ci-01
runner-02 → red-02 → docker-ci-02
runner-03 → red-03 → docker-ci-03
runner-04 → gate-network → GitHub (sin DinD)
```

No existe conectividad necesaria entre los pares. Ninguno monta el socket Docker del host.

## Recursos predeterminados

Por instancia:

```env
RUNNER_CPUS=0.50
RUNNER_MEMORY=5g
DIND_CPUS=0.75
DIND_MEMORY=4g
DIND_PIDS_LIMIT=1024
DIND_SHM_SIZE=512m
```

Máximo agregado aproximado del stack, considerando los límites de memoria y CPU de los seis contenedores:

- CPU: 3,75 CPU lógicas;
- memoria: 27 GiB;
- almacenamiento: 45 GiB compartidos como techo en instalaciones nuevas.

Los límites son máximos, no reservas. Antes de habilitar tres jobs pesados simultáneos en una VM compartida, validar capacidad real del host y conservar margen para el sistema operativo y el stack productivo.

## Datos persistentes

```text
/srv/coferlandia-ci/
├── runner-01/
├── runner-02/
├── runner-03/
├── work-01/
├── work-02/
├── work-03/
├── cache-01/
├── cache-02/
├── cache-03/
├── docker-01/
├── docker-02/
├── docker-03/
├── certs-01/
├── certs-02/
└── certs-03/
```

## Programación en GitHub

Los tres runners usan las mismas etiquetas personalizadas. GitHub decide cuál está disponible:

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

Los jobs pesados no deben codificar un runner individual. Los jobs de agregación/Gate deben usar `runs-on: [self-hosted, coferlandia-ci-gate]` para no competir con los workers PostgreSQL/Docker.
