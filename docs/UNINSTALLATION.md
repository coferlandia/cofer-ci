# Desinstalación completa

## 1. Desregistrar los runners

```bash
./scripts/unregister-runners.sh
```

Confirme en GitHub que desaparecieron `coferlandia-ci-01` y `coferlandia-ci-02`.

## 2. Retirar systemd

```bash
sudo ./scripts/uninstall-systemd.sh
```

## 3. Detener y eliminar contenedores

```bash
docker compose down --remove-orphans
```

## 4. Eliminar la imagen local opcionalmente

```bash
docker image rm coferlandia/ci-runner:latest
```

## 5. Eliminar almacenamiento

Sólo después de confirmar que no se necesitan credenciales, workspaces ni cachés:

```bash
sudo umount /srv/coferlandia-ci
sudo sed -i '\|/var/lib/coferlandia-ci.img /srv/coferlandia-ci|d' /etc/fstab
sudo rm -f /var/lib/coferlandia-ci.img
sudo rmdir /srv/coferlandia-ci
```

## 6. Eliminar el proyecto

```bash
cd ~/docker-projects
rm -rf coferlandia-ci-runner
```
