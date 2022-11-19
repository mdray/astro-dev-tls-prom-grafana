#!/bin/bash

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

[ -f nginx/fullchain.pem ] || (echo '#'; echo "# WARNING: TLS proxy won't work without cert chain at 'nginx/fullchain.pem'"; echo '#')
[ -f nginx/privkey.pem ] ||   (echo '#'; echo "# WARNING: TLS proxy won't work without private key at 'nginx/privkey.pem'"; echo '#')

mkdir -p log

# Limit the scheduler to a percentage of system memory. Important for load tests.
# Expressed as a float between 0 and 1.
if [ -z ${SCHEDULER_MEM_PERCENT} ]; then
  export SCHEDULER_MEM_PERCENT=0.75
fi

echo
echo '### Pulling docker images.'
echo
docker pull quay.io/astronomer/ap-statsd-exporter
docker pull prom/prometheus
docker pull grafana/grafana-oss
docker pull vault
docker pull nginx

set -e
if [ -d $ASTRODIR ]; then
  bakdir=.bak.${ASTRODIR}.$(date +%Y.%m.%d-%H.%M.%S)
  mv $ASTRODIR $bakdir
  echo Backing up existing dev directory to $bakdir.tbz2
  tar -cjf $bakdir.tbz2 $bakdir
  rm -fr $bakdir
fi

echo
echo '### Initializing new Astro dev directory.'
echo
mkdir -p $ASTRODIR
cd $ASTRODIR
astro dev init

echo
echo '### Copying Airflow demo content.'
echo
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

echo
echo '### Starting Astro dev.'
echo
astro dev start -n
cd ..

network=$(docker inspect $(docker ps --format {{.Names}} | grep $ASTRODIR | grep postgres-)  -f "{{json .NetworkSettings.Networks }}" | jq -M -r '.[] | .NetworkID')

echo
echo '### Raise postgres connection limit.'
echo
until (docker ps | grep $ASTRODIR | grep postgres >/dev/null); do sleep 0.5; done
pgcontainer=$(docker ps | grep $ASTRODIR | grep postgres | cut -f1 -d' ')
until (docker exec -it $pgcontainer ls >/dev/null); do sleep 0.5; done
docker exec -it $pgcontainer sed -i 's/max_connections = .*/max_connections = 1000/' /var/lib/postgresql/data/postgresql.conf

echo
echo '### Set scheduler memory limits.'
echo
# Determine good scheduler memory limits. Too many concurrent tasks will cause swapping without this.
scheduler_ram_k=$(printf "%.0fk\n" $(echo "$(head -n1 /proc/meminfo | awk '{print $2}')  * $SCHEDULER_MEM_PERCENT " | bc))
scheduler_swap_k=$(printf "%ik" $(head -n1 /proc/meminfo | awk '{print $2}'))
until (docker ps | grep $ASTRODIR | grep scheduler >/dev/null); do sleep 0.5; done
docker container update --memory $scheduler_ram_k --memory-swap $scheduler_swap_k  $(docker ps | grep scheduler-1 | awk '{print $1}')

echo
echo '### Starting statsd-exporter, prometheus, grafana.'
echo
docker run -d --name statsd \
  --restart unless-stopped \
  --network $network \
  -p 9102:9102/tcp \
  -p 9125:9125/tcp \
  -p 9125:9125/udp \
  quay.io/astronomer/ap-statsd-exporter

docker run -d \
  --restart unless-stopped \
  --network $network \
  --name prom \
  -p 9090:9090 \
  -v $PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

docker run -d -p 3000:3000 \
  --restart unless-stopped \
  --network $network \
  --name grafana \
  -v $PWD/grafana:/etc/grafana \
  grafana/grafana-oss

docker run -d \
  -p 8200:8200 \
  --restart unless-stopped \
  --network $network \
  --name vault \
  --cap-add=IPC_LOCK \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=root' \
  vault

webserver=$(docker ps --format {{.Names}} | grep $ASTRODIR | grep webserver-)
sed "s/AIRFLOW-WEBSERVER/$webserver/" < nginx/nginx.conf.template > nginx/nginx.conf
docker run -d \
  -p 80:80 \
  -p 443:443 \
  -p 3443:3443 \
  -p 8201:8201 \
  --restart unless-stopped \
  --network $network \
  --name nginx \
  -v $PWD/nginx:/etc/nginx/ \
  nginx


echo
echo '### Configuring Vault.'
echo
set +e
vault/setup.sh
set -e

echo
echo '### Restarting Astro.'
echo
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