# Conexión a la VM y carga del proyecto

Esta guía parte de una computadora Windows usando Git Bash. Reemplace los valores de ejemplo por los datos reales de la VM.

## 1. Identificar los datos de conexión

Necesita:

- dirección IP pública o nombre DNS de la VM;
- usuario SSH, normalmente `ubuntu`;
- clave privada SSH;
- puerto SSH, normalmente `22`.

Ejemplo de variables en Git Bash:

```bash
export VM_HOST="IP_O_DNS_DE_LA_VM"
export VM_USER="ubuntu"
export VM_PORT="22"
export SSH_KEY="$HOME/.ssh/coferlandia.key"
```

Compruebe que la clave exista:

```bash
ls -l "$SSH_KEY"
chmod 600 "$SSH_KEY"
```

Si la clave está en otra carpeta, use una ruta válida para Git Bash, por ejemplo:

```bash
export SSH_KEY="/c/Users/Diego/.ssh/coferlandia.key"
```

## 2. Probar la conexión SSH

```bash
ssh -p "$VM_PORT" -i "$SSH_KEY" "$VM_USER@$VM_HOST"
```

La primera vez, SSH puede pedir confirmar la huella del servidor. Confirme únicamente después de verificar que la IP o el DNS sean correctos.

Dentro de la VM, confirme identidad y ubicación:

```bash
whoami
hostname
pwd
```

Salga para continuar la carga desde la computadora local:

```bash
exit
```

## 3. Ubicar el ZIP local

En Git Bash, cambie a la carpeta donde descargó el paquete:

```bash
cd ~/Downloads
ls -lh coferlandia-ci-runner-0.3.0.zip*
```

Los nombres esperados son:

```text
coferlandia-ci-runner-0.3.0.zip
coferlandia-ci-runner-0.3.0.zip.sha256
```

## 4. Crear una carpeta temporal en la VM

```bash
ssh -p "$VM_PORT" -i "$SSH_KEY" "$VM_USER@$VM_HOST" \
  'mkdir -p "$HOME/uploads" "$HOME/docker-projects"'
```

La estructura elegida será:

```text
/home/ubuntu/uploads/                    paquetes de instalación temporales
/home/ubuntu/docker-projects/            proyectos Docker independientes
/home/ubuntu/docker-projects/coferlandia-ci-runner/
```

Si el usuario no es `ubuntu`, `$HOME` se resolverá automáticamente a su directorio real.

## 5. Subir el ZIP y el checksum

Desde Git Bash:

```bash
scp -P "$VM_PORT" -i "$SSH_KEY" \
  coferlandia-ci-runner-0.3.0.zip \
  coferlandia-ci-runner-0.3.0.zip.sha256 \
  "$VM_USER@$VM_HOST:~/uploads/"
```

Compruebe que llegaron:

```bash
ssh -p "$VM_PORT" -i "$SSH_KEY" "$VM_USER@$VM_HOST" \
  'ls -lh "$HOME/uploads/coferlandia-ci-runner-0.3.0.zip"*'
```

## 6. Verificar integridad en la VM

Conéctese:

```bash
ssh -p "$VM_PORT" -i "$SSH_KEY" "$VM_USER@$VM_HOST"
```

Luego:

```bash
cd ~/uploads
sha256sum -c coferlandia-ci-runner-0.3.0.zip.sha256
```

Debe terminar con:

```text
coferlandia-ci-runner-0.3.0.zip: OK
```

Si el archivo `.sha256` contiene una ruta local en vez del nombre simple, verifique manualmente:

```bash
sha256sum coferlandia-ci-runner-0.3.0.zip
cat coferlandia-ci-runner-0.3.0.zip.sha256
```

## 7. Instalar `unzip` y utilidades base

```bash
sudo apt update
sudo apt install -y \
  ca-certificates curl git jq unzip \
  util-linux e2fsprogs procps iproute2
```

## 8. Extraer como proyecto independiente

Para una instalación nueva:

```bash
cd ~/docker-projects
unzip ~/uploads/coferlandia-ci-runner-0.3.0.zip
cd ~/docker-projects/coferlandia-ci-runner
```

Compruebe el contenido:

```bash
pwd
cat VERSION
ls -la
```

El resultado esperado de `pwd` es semejante a:

```text
/home/ubuntu/docker-projects/coferlandia-ci-runner
```

## 9. Conservar el paquete original

Puede conservar el ZIP en `~/uploads` hasta completar la instalación. Después de verificar que todo funciona, puede eliminarlo:

```bash
rm -f ~/uploads/coferlandia-ci-runner-0.3.0.zip \
      ~/uploads/coferlandia-ci-runner-0.3.0.zip.sha256
```

No elimine el directorio del proyecto ni `/srv/coferlandia-ci`.

## 10. Publicación de puertos

Este proyecto no requiere publicar puertos:

- no agregue reglas nuevas de ingreso en el firewall de la nube;
- no agregue reglas nuevas en UFW para los runners;
- no configure un dominio ni proxy reverso;
- no exponga el puerto `2376`;
- no monte el socket `/var/run/docker.sock` dentro de los runners.

Sólo se requieren conexiones salientes HTTPS por TCP `443` desde la VM hacia GitHub, registries de contenedores y repositorios de paquetes usados por los builds.

Para revisar los puertos antes y después:

```bash
sudo ss -tulpen
```

La instalación del runner no debería agregar un nuevo puerto en escucha sobre la interfaz pública.

## 11. Continuar la instalación

Con el proyecto extraído:

```bash
./scripts/host-survey.sh before
cp .env.example .env
nano .env
sudo ./scripts/install-host.sh
./scripts/check-prerequisites.sh
./scripts/register-runners.sh
sudo ./scripts/install-systemd.sh
./scripts/verify-installation.sh
```

El proceso completo y el relevamiento comparativo están descritos en:

- [INSTALLATION.md](INSTALLATION.md)
- [HOST_SURVEY.md](HOST_SURVEY.md)
- [GITHUB_CONFIGURATION.md](GITHUB_CONFIGURATION.md)
- [MONITORING.md](MONITORING.md)
