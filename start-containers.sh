#!/bin/bash -x

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

echo Starting Astro dev environment
set -e

cat > prometheus.yml <<EOF
global:
    scrape_interval: 10s
    evaluation_interval: 10s
    scrape_timeout: 10s
    external_labels:
        monitor: 'astro-dev'
scrape_configs:
  - job_name: 'airflow-statsd-exporter'
    static_configs:
      - targets: ['statsd:9102']
EOF

mkdir -p $ASTRODIR
cd $ASTRODIR
astro dev init

cp ../simple_wide_dag.py dags

cat > .env <<EOF
AIRFLOW__METRICS__STATSD_ON=True
AIRFLOW__METRICS__STATSD_HOST=statsd
AIRFLOW__METRICS__STATSD_PORT=9125
AIRFLOW__METRICS__STATSD_PREFIX=airflow

AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True

AIRFLOW__CORE__PARALLELISM=128
AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=128

EOF

astro dev start

# Raise Postgresql max_conn from 100 to 200
pgcontainer=$(docker ps | grep $ASTRODIR | grep postgres | cut -f1 -d' ')
docker exec -it $pgcontainer sed -i 's/max_connections = 100/max_connections = 200/' /var/lib/postgresql/data/postgresql.conf

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
  -v $PWD/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

docker run -d -p 3000:3000 \
  --restart unless-stopped \
  --network $network \
  --name grafana \
  -v $PWD/grafana:/etc/grafana \
  grafana/grafana-oss 

sed "s/AIRFLOW-WEBSERVER/$webserver/" < nginx/nginx.conf.template > nginx/nginx.conf
docker run -d -p 80:80 -p 3443:3443 -p 8443:8443 \
  --restart unless-stopped \
  --network $network \
  --name nginx \
  -v $PWD/nginx:/etc/nginx/ \
  nginx 
