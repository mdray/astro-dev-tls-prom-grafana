#!/bin/bash

. config.env

if [ -z ${ASTRODIR} ]; then
  echo "\$ASTRODIR not defined"
  exit 1
fi

# Limit the scheduler to a percentage of system memory. Important for load tests.
# Expressed as a float between 0 and 1.
if [ -z ${SCHEDULER_MEM_PERCENT} ]; then
  export SCHEDULER_MEM_PERCENT=0.75
fi

network=$(docker inspect $(docker ps --format {{.Names}} | grep $ASTRODIR | grep postgres-)  -f "{{json .NetworkSettings.Networks }}" | jq -M -r '.[] | .NetworkID')

echo
echo '### Raise postgres connection limit.'
echo
until (docker ps | grep $ASTRODIR | grep postgres >/dev/null); do sleep 0.5; done
pgcontainer=$(docker ps | grep $ASTRODIR | grep postgres | cut -f1 -d' ')
until (docker exec -it $pgcontainer ls >/dev/null); do sleep 0.5; done
docker exec -it $pgcontainer sed -i 's/max_connections = .*/max_connections = 5000/' /var/lib/postgresql/data/postgresql.conf

echo
echo '### Set scheduler memory limits.'
echo
# Determine good scheduler memory limits. Too many concurrent tasks will cause swapping without this.
scheduler_ram_k=$(printf "%.0fk\n" $(echo "$(head -n1 /proc/meminfo | awk '{print $2}')  * $SCHEDULER_MEM_PERCENT " | bc))
scheduler_swap_k=$(printf "%ik" $(head -n1 /proc/meminfo | awk '{print $2}'))
until (docker ps | grep $ASTRODIR | grep scheduler >/dev/null); do sleep 0.5; done
docker container update --memory $scheduler_ram_k --memory-swap $scheduler_swap_k  $(docker ps | grep scheduler-1 | awk '{print $1}')
