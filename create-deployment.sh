#!/bin/bash

NAME=jacobm-scale

astro deployment create \
  --cluster-id cl98xxw8y0wnl0tyycizy24kl \
  --name $NAME \
  --runtime-version 6.0.2 \
  --scheduler-au 20 \
  --scheduler-replicas 2 \
  --workspace-id cl81pguhg3568354syfo88o4kjz

# Requires interactive input to specify the worker queue
# TODO - github issue to add --worker-queue option
astro deployment worker-queue update \
  --deployment-name $NAME \
  --max-count 30 \
  --min-count 30 \
  --worker-type m5.xlarge \
  --concurrency 64

astro deployment variable update \
 AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True \
 AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=2005 \
 AIRFLOW__CORE__PARALLELISM=2005 \
 AIRFLOW__METRICS__STATSD_ON=True \
 AIRFLOW__METRICS__STATSD_HOST=stats-aws.cosmic-security.net \
 AIRFLOW__METRICS__STATSD_PORT=9125 \
 AIRFLOW__METRICS__STATSD_PREFIX=airflow \
 AIRFLOW_SCHEDULER_MAX_TIS_PER_QUERY=256 \
 --deployment-name $NAME

# Create API key in UI and save in your password manager

# Set default pool size to 2000 in UI


