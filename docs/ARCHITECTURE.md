# Arquitectura y concurrencia

## Objetivo

La versión 0.3.0 permite ejecutar dos jobs simultáneos sin permitir que un job interfiera con el ambiente Docker del otro ni con los contenedores productivos del host.

## Componentes

| Componente | Función | Estado persistente |
|---|---|---|
| `runner-01` | Listener GitHub Actions 1 | `runner-01`, `work-01`, `cache-01` |
| `docker-ci-01` | Docker exclusivo del runner 1 | `docker-01`, `certs-01` |
| `runner-02` | Listener GitHub Actions 2 | `runner-02`, `work-02`, `cache-02` |
| `docker-ci-02` | Docker exclusivo del runner 2 | `docker-02`, `certs-02` |
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

Además, los hooks defensivos eliminan recursos residuales antes y después de cada job. En un daemon compartido, un job podría borrar contenedores, redes o volúmenes utilizados por el otro.

Docker Engine no ofrece namespaces independientes por cliente. Por ese motivo, la frontera segura y simple es un daemon por runner.

## Concurrencia efectiva

- Cada `Runner.Listener` ejecuta un solo job.
- Existen dos listeners.
- Capacidad máxima: dos jobs simultáneos.
- Un tercer job compatible queda en cola.
- Dentro de cada job pueden ejecutarse múltiples procesos y contenedores.

## Aislamiento

```text
runner-01 → red-01 → docker-ci-01
runner-02 → red-02 → docker-ci-02
```

No existe conectividad necesaria entre ambos pares. Ninguno monta el socket Docker del host.

## Recursos predeterminados

Por instancia:

```env
RUNNER_CPUS=0.50
RUNNER_MEMORY=768m
DIND_CPUS=1.25
DIND_MEMORY=2500m
```

Máximo agregado aproximado del stack:

- CPU: 3,5 CPU lógicas;
- memoria: 6,5 GiB;
- almacenamiento: 30 GiB compartidos como techo.

Los límites son máximos, no reservas. Para una VM con otras cargas, observe el primer período de uso y ajústelos según la duración de los jobs y la latencia de los servicios productivos.

## Datos persistentes

```text
/srv/coferlandia-ci/
├── runner-01/       credenciales y distribución del runner 1
├── runner-02/       credenciales y distribución del runner 2
├── work-01/         checkouts y temporales del runner 1
├── work-02/         checkouts y temporales del runner 2
├── cache-01/        NuGet/npm/pip/toolcache del runner 1
├── cache-02/        NuGet/npm/pip/toolcache del runner 2
├── docker-01/       datos del Docker CI 1
├── docker-02/       datos del Docker CI 2
├── certs-01/        TLS del par 1
└── certs-02/        TLS del par 2
```

## Programación en GitHub

Ambos runners usan las mismas etiquetas personalizadas. GitHub decide cuál está disponible:

```yaml
runs-on: [self-hosted, coferlandia-ci]
```

No codifique `coferlandia-ci-01` o `coferlandia-ci-02` en los workflows salvo que exista una necesidad diagnóstica excepcional.
