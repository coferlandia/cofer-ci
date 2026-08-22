#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "========== CONTENEDORES =========="
docker compose ps

RUNNER_CONTAINER="$(
  docker ps \
    --filter "name=coferlandia-ci" \
    --format '{{.ID}}' |
  head -n 1
)"

if [ -z "$RUNNER_CONTAINER" ]; then
  echo
  echo "ERROR: no se encontró el contenedor del CI runner"
  exit 1
fi

echo
echo "========== RUNNER =========="
docker inspect \
  --format 'Nombre={{.Name}} Estado={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}} Reinicios={{.RestartCount}} Inicio={{.State.StartedAt}}' \
  "$RUNNER_CONTAINER"

echo
echo "========== PROCESOS ACTIVOS =========="
docker exec "$RUNNER_CONTAINER" sh -lc '
  id
  echo
  ps aux | grep -E "[R]unner.Listener|[R]unner.Worker|[r]un.sh"
'

echo
echo "========== ACCESO A DOCKER =========="
docker exec "$RUNNER_CONTAINER" sh -lc '
  echo "Docker CLI: $(command -v docker || echo NO_ENCONTRADO)"
  echo "DOCKER_HOST: ${DOCKER_HOST:-<no definido>}"
  docker version --format "Cliente={{.Client.Version}} Servidor={{.Server.Version}}"
  docker info --format "Docker operativo: {{.ServerVersion}} | Contenedores={{.Containers}} | Imágenes={{.Images}}"
'

echo
echo "========== JOBS Y LOGS RECIENTES =========="
docker compose logs --tail=100 --no-color

echo
echo "========== RECURSOS =========="
docker stats --no-stream "$RUNNER_CONTAINER"

echo
echo "========== RESULTADO =========="
echo "OK si:"
echo "- el contenedor está running"
echo "- Runner.Listener o Runner.Worker aparece activo"
echo "- docker version muestra cliente y servidor"
echo "- los logs no contienen errores recientes"
echo "- los reinicios no aumentan inesperadamente"
