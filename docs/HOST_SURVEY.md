# Relevamiento de la VM antes y después

El objetivo es medir el impacto real de los dos runners sobre la VM compartida y conservar evidencia para ajustar CPU, memoria y almacenamiento.

## Qué registra

`scripts/host-survey.sh` recopila:

- sistema operativo, kernel, arquitectura y uptime;
- cantidad y modelo de CPU;
- carga de 1, 5 y 15 minutos;
- memoria total, usada, disponible y swap;
- capacidad, uso e inodos de todos los filesystems;
- dispositivos de bloque y montajes;
- versión y estado de Docker;
- cantidad de contenedores, imágenes, volúmenes y redes;
- `docker system df`;
- consumo instantáneo de los contenedores existentes;
- procesos con mayor uso de CPU y memoria;
- puertos TCP/UDP en escucha;
- servicios `systemd` fallidos;
- estado del filesystem dedicado a CI, cuando ya existe.

Cada ejecución genera:

```text
reports/host-surveys/<fecha>-<host>-<etiqueta>.txt
reports/host-surveys/<fecha>-<host>-<etiqueta>.metrics
```

El `.txt` es para inspección humana. El `.metrics` sirve para la comparación automática.

## 1. Relevamiento previo

Después de extraer el ZIP, pero antes de crear el almacenamiento o levantar contenedores:

```bash
cd ~/docker-projects/coferlandia-ci-runner
./scripts/host-survey.sh before
```

Espere a que la VM esté relativamente tranquila. Evite tomar la medición mientras hay actualizaciones, backups o cargas extraordinarias.

Liste los archivos generados:

```bash
ls -lh reports/host-surveys/
```

Revise el informe:

```bash
less reports/host-surveys/*-before.txt
```

## 2. Instalar el runner

Complete la instalación:

```bash
cp .env.example .env
nano .env
sudo ./scripts/install-host.sh
./scripts/check-prerequisites.sh
./scripts/register-runners.sh
sudo ./scripts/install-systemd.sh
sudo ./scripts/verify-installation.sh
```

## 3. Relevamiento posterior en reposo

Espere entre dos y cinco minutos para que terminen el arranque, healthchecks y descargas iniciales. No ejecute todavía un workflow.

```bash
./scripts/host-survey.sh after-idle
```

Esto mide el costo base de mantener los dos runners conectados y los dos daemons Docker CI encendidos sin trabajo.

## 4. Comparar antes y después

Seleccione los archivos:

```bash
BEFORE_METRICS="$(ls -1t reports/host-surveys/*-before.metrics | head -n1)"
AFTER_METRICS="$(ls -1t reports/host-surveys/*-after-idle.metrics | head -n1)"
```

Genere la comparación:

```bash
./scripts/compare-host-surveys.sh \
  "$BEFORE_METRICS" \
  "$AFTER_METRICS" \
  | tee reports/host-surveys/comparison-before-after-idle.txt
```

La tabla muestra diferencias de:

- memoria usada y disponible;
- swap;
- espacio usado y disponible en `/`;
- contenedores, imágenes y volúmenes Docker;
- uso del filesystem de CI.

La carga de CPU se muestra como contexto, pero no se resta automáticamente porque es una medición instantánea y puede fluctuar por procesos ajenos al runner.

## 5. Medir durante un job

Para conocer el peor caso práctico, inicie el workflow de smoke test o un CI real. Mientras esté ejecutándose:

```bash
./scripts/host-survey.sh during-ci
```

Compare con el estado previo:

```bash
DURING_METRICS="$(ls -1t reports/host-surveys/*-during-ci.metrics | head -n1)"
./scripts/compare-host-surveys.sh \
  "$BEFORE_METRICS" \
  "$DURING_METRICS" \
  | tee reports/host-surveys/comparison-before-during-ci.txt
```

También puede observar en vivo:

```bash
docker stats coferlandia-ci-runner-01 coferlandia-ci-runner-02 coferlandia-ci-docker-01 coferlandia-ci-docker-02
watch -n 2 'free -h; echo; df -h / /srv/coferlandia-ci'
```

Finalice `watch` con `Ctrl+C`.

## 6. Medir después del primer job y la limpieza

Cuando termine el workflow y el hook posterior haya eliminado contenedores y volúmenes temporales:

```bash
./scripts/status.sh
./scripts/host-survey.sh after-first-job
```

Esta medición permite verificar cuánto quedó retenido como caché útil.

## 7. Indicadores para decidir ajustes

Revise especialmente:

- `MemAvailable`: debería quedar margen suficiente para el stack productivo;
- swap usada: crecimiento sostenido puede indicar presión de memoria;
- carga por CPU: compare la carga de 1 minuto con la cantidad de CPU lógicas;
- filesystem raíz: debe conservar margen aunque el filesystem de CI sea limitado;
- `/srv/coferlandia-ci`: debe permanecer por debajo del umbral normal de limpieza;
- reinicios de contenedores: deben mantenerse en cero durante operación normal;
- servicios fallidos: la instalación no debería agregar fallos de `systemd`;
- puertos: no debería aparecer un puerto público nuevo del runner.

## 8. Valores iniciales a revisar

La configuración predeterminada establece máximos, no reservas:

```env
RUNNER_CPUS=0.50
RUNNER_MEMORY=3g
DIND_CPUS=1.25
DIND_MEMORY=2500m
CI_STORAGE_SIZE=30G
```

El límite de memoria del listener debe ser suficiente para instalaciones de dependencias y suites completas ejecutadas directamente en el runner. Ajuste estos valores con evidencia de jobs reales y conserve margen para el stack productivo. Si la VM queda con poca memoria disponible, reduzca primero `DIND_MEMORY` o limite los servicios levantados por los tests.

## 9. Copiar los reportes a la PC

Desde Git Bash en Windows:

```bash
mkdir -p ~/Downloads/coferlandia-ci-surveys
scp -P "$VM_PORT" -i "$SSH_KEY" -r \
  "$VM_USER@$VM_HOST:~/docker-projects/coferlandia-ci-runner/reports/host-surveys/" \
  ~/Downloads/coferlandia-ci-surveys/
```

Los informes pueden contener nombres de contenedores, procesos, montajes y puertos. Trátelos como información interna de infraestructura.
