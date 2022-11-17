#!/bin/bash

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

set -e

# remove existing containers
PATTERN="${ASTRODIR}_|/airflow:latest | prom/prometheus | grafana/grafana-oss | quay.io/astronomer/ap-statsd-exporter | nginx | vault "
echo Removing any Astro containers matching "$PATTERN"
docker ps -a | grep -v CONTAINER | egrep "$PATTERN" >/dev/null && \
docker ps -a | grep -v CONTAINER | egrep "$PATTERN" | awk '{print $1}' | xargs docker rm -f -v

# prune networks
echo Pruning networks
docker network prune -f

# echo Deleting Astro docker volumes
echo Deleting volumes
docker volume ls | grep -v CONTAINER | egrep "$PATTERN" && \
docker volume ls | grep -v CONTAINER | egrep "$PATTERN" | awk '{print $2}' | xargs docker volume rm

rm -fr $ASTRODIR

./start-astro-dev-stack.sh

# mkdir -p $ASTRODIR && cd $ASTRODIR && astro dev restart && cd -

# # grafana https
# www-browser https://localhost.cosmic-security.net:3443/

# # grafana http
# www-browser http://localhost:3000/

# # airflow https
# www-browser https://localhost.cosmic-security.net:8443/