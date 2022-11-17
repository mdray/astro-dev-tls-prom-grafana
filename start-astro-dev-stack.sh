#!/bin/bash -x

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

echo; echo Pulling required docker images; echo
docker pull quay.io/astronomer/astro-runtime
docker pull quay.io/astronomer/ap-statsd-exporter
docker pull prom/prometheus
docker pull grafana/grafana-oss
docker pull vault
docker pull nginx


echo Starting Astro dev environment
set -e
if [ -d $ASTRODIR ]; then
  mv -v $ASTRODIR .bak.${ASTRODIR}.$(date +%Y.%m.%d-%H.%M.%S)
fi
mkdir -p $ASTRODIR
cd $ASTRODIR
astro dev init

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
AWS_DEFAULT_REGION=us-east-2

EOF

astro dev start

# Tune for higher concurrency
# Raise Postgresql max_conn from 100 to 1000
pgcontainer=$(docker ps | grep $ASTRODIR | grep postgres | cut -f1 -d' ')
docker exec -it $pgcontainer sed -i 's/max_connections = .*/max_connections = 1000/' /var/lib/postgresql/data/postgresql.conf
docker container update --memory 16g --memory-swap 18g  $(docker ps | grep scheduler-1 | awk '{print $1}')

cd ..

# network=$(docker inspect $(docker ps | grep scheduler | cut -f1 -d' ') -f "{{json .NetworkSettings.Networks }}" | jq -r '.[] | .NetworkID' )

network=$(docker inspect $(docker ps --format {{.Names}} | grep $ASTRODIR | grep scheduler-)  -f "{{json .NetworkSettings.Networks }}" | jq -M -r '.[] | .NetworkID')
webserver=$(docker ps --format {{.Names}} | grep webserver-)


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
  --restart unless-stopped \
  --network $network \
  --name vault \
  --cap-add=IPC_LOCK \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=root' \
  vault

sed "s/AIRFLOW-WEBSERVER/$webserver/" < nginx/nginx.conf.template > nginx/nginx.conf
docker run -d \
  -p 80:80 \
  -p 3443:3443 \
  -p 8200:8200 \
  -p 8443:8443 \
  --restart unless-stopped \
  --network $network \
  --name nginx \
  -v $PWD/nginx:/etc/nginx/ \
  nginx 

vault/setup.sh

cd $ASTRODIR && astro dev restart

