#!/bin/bash

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

[ -f nginx/fullchain.pem ] || (echo '#'; echo "# WARNING: TLS proxy won't work without cert chain at 'nginx/fullchain.pem'"; echo '#')
[ -f nginx/privkey.pem ] ||   (echo '#'; echo "# WARNING: TLS proxy won't work without private key at 'nginx/privkey.pem'"; echo '#')


# Limit the scheduler to a percentage of system memory. Important for load tests.
# Expressed as a float between 0 and 1.
if [ -z ${SCHEDULER_MEM_PERCENT} ]; then
  export SCHEDULER_MEM_PERCENT=0.75
fi

echo
echo '#################################################################################'
echo 'Pulling docker images and starting Airflow project in background.'

# echo
LN=00
docker pull quay.io/astronomer/ap-statsd-exporter >log/$LN.docker.pull.ap-statsd-exporter.out 2>log/$LN.docker.pull.ap-statsd-exporter.err &
docker pull prom/prometheus >log/$LN.docker.pull.prometheus.out 2>log/$LN.docker.pull.prometheus.err &
docker pull grafana/grafana-oss >log/$LN.docker.pull.grafana.out 2>log/$LN.docker.pull.grafana.err &
docker pull vault >log/$LN.docker.pull.vault.out 2>log/$LN.docker.pull.vault.err &
docker pull nginx >log/$LN.docker.pull.nginx.out 2>log/$LN.docker.pull.nginx.err &

set -e
if [ -d $ASTRODIR ]; then
  bakdir=.bak.${ASTRODIR}.$(date +%Y.%m.%d-%H.%M.%S)
  mv $ASTRODIR $bakdir
  echo Backing up existing dev directory to $bakdir.tbz2
  tar -cjf $bakdir.tbz2 $bakdir
  rm -fr $bakdir
fi

echo Starting initial Astro dev environment
mkdir -p $ASTRODIR
cd $ASTRODIR
astro dev init

echo
echo '### Copying Airflow demo content.'
cp -v ../content/*.py dags
cp -v ../content/airflow_settings.yaml .
cp -v ../content/requirements.txt .

cat > .env <<EOF
AIRFLOW__METRICS__STATSD_ON=True
AIRFLOW__METRICS__STATSD_HOST=statsd
AIRFLOW__METRICS__STATSD_PORT=9125
AIRFLOW__METRICS__STATSD_PREFIX=airflow

AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True

AIRFLOW__CORE__PARALLELISM=128
AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=128

AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL=10

AIRFLOW__CORE__ENABLE_XCOM_PICKLING=True

EOF

LN=01
astro dev start -n >../log/$LN.astro.dev.start.out 2>../log/$LN.astro.dev.start.err &
PID_ASTRO_START=$!
cd ..

echo
echo '#################################################################################'
echo 'Waiting for Airflow Docker bridge network to come up.'

until (docker network ls | grep $ASTRODIR); do sleep 0.5; done
until (docker ps | grep $ASTRODIR | grep postgres >/dev/null); do sleep 0.5; done
network=$(docker inspect $(docker ps --format {{.Names}} | grep $ASTRODIR | grep postgres-)  -f "{{json .NetworkSettings.Networks }}" | jq -M -r '.[] | .NetworkID')

echo
echo '#################################################################################'
echo 'Starting statsd-exporter, prometheus, grafana in background.'

LN=02
docker run -d --name statsd \
  --restart unless-stopped \
  --network $network \
  -p 9102:9102/tcp \
  -p 9125:9125/tcp \
  -p 9125:9125/udp \
  quay.io/astronomer/ap-statsd-exporter >log/$LN.docker.run.statsd.out 2>log/$LN.docker.run.statsd.err &

docker run -d \
  --restart unless-stopped \
  --network $network \
  --name prom \
  -p 9090:9090 \
  -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus >log/$LN.docker.run.prometheus.out 2>log/$LN.docker.run.prometheus.err &

docker run -d -p 3000:3000 \
  --restart unless-stopped \
  --network $network \
  --name grafana \
  -v $PWD/grafana:/etc/grafana \
  grafana/grafana-oss >log/$LN.docker.run.prometheus.out 2>log/$LN.docker.run.prometheus.err & 

docker run -d \
  -p 8200:8200 \
  --restart unless-stopped \
  --network $network \
  --name vault \
  --cap-add=IPC_LOCK \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=root' \
  vault >log/$LN.docker.run.vault.out 2>log/$LN.docker.run.vault.err & 
PID_VAULT_START=$!

echo
echo '#################################################################################'
echo 'Astro performance tuning.'

# Determine good scheduler memory limits. Too many concurrent tasks will cause swapping without this.
scheduler_ram_k=$(printf "%.0fk\n" $(echo "$(head -n1 /proc/meminfo | awk '{print $2}')  * $SCHEDULER_MEM_PERCENT " | bc))
scheduler_swap_k=$(printf "%ik" $(head -n1 /proc/meminfo | awk '{print $2}'))

# Raise postgres connection limits
until (docker ps | grep $ASTRODIR | grep postgres >/dev/null); do sleep 0.5; done
pgcontainer=$(docker ps | grep $ASTRODIR | grep postgres | cut -f1 -d' ')
until (docker exec -it $pgcontainer ls >/dev/null); do sleep 0.5; done
docker exec -it $pgcontainer sed -i 's/max_connections = .*/max_connections = 1000/' /var/lib/postgresql/data/postgresql.conf

# Apply scheduler memory limits
until (docker ps | grep $ASTRODIR | grep scheduler >/dev/null); do sleep 0.5; done
docker container update --memory $scheduler_ram_k --memory-swap $scheduler_swap_k  $(docker ps | grep scheduler-1 | awk '{print $1}')

echo
echo '#################################################################################'
echo 'Starting nginx in background.'

# Get webserver container name. Required for nginx config.
until (docker ps | grep $ASTRODIR | grep webserver >/dev/null); do sleep 0.5; done
webserver=$(docker ps --format {{.Names}} | grep $ASTRODIR | grep webserver-)


sed "s/AIRFLOW-WEBSERVER/$webserver/" < nginx/nginx.conf.template > nginx/nginx.conf
LN=03
docker run -d \
  -p 80:80 \
  -p 443:443 \
  -p 3443:3443 \
  -p 8201:8201 \
  --restart unless-stopped \
  --network $network \
  --name nginx \
  -v $PWD/nginx:/etc/nginx/ \
  nginx >log/$LN.docker.run.nginx.out 2>log/$LN.docker.run.nginx.err & 

echo
echo '#################################################################################'
echo 'Configuring Vault.'


wait $PID_VAULT_START
set +e
vault/setup.sh
set -e

echo
echo '#################################################################################'
echo 'Waiting for initial Astro startup to complete.'
wait $PID_ASTRO_START

echo
echo '#################################################################################'
echo 'Restarting Astro.'

cd $ASTRODIR && astro dev stop
astro dev start -n

echo
echo "Airflow:          http://localhost.${DOMAIN}:8080/"
echo "Airflow TLS:      https://localhost.${DOMAIN}/"
echo "Grafana:          http://localhost.${DOMAIN}:3000/"
echo "Grafana TLS:      https://localhost.${DOMAIN}:3443/"
echo "Vault:            http://localhost.${DOMAIN}:8200/"
echo "Vault TLS:        https://localhost.${DOMAIN}:8201/"
echo