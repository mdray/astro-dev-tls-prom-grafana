#!/bin/bash

. config.env

echo
echo "Airflow:          http://${NODENAME}.${DOMAIN}:8080/"
echo "Airflow TLS:      https://${NODENAME}.${DOMAIN}/"
echo "Grafana:          http://${NODENAME}.${DOMAIN}:3000/"
echo "Grafana TLS:      https://${NODENAME}.${DOMAIN}:3443/"
echo "Vault:            http://${NODENAME}.${DOMAIN}:8200/"
echo "Vault TLS:        https://${NODENAME}.${DOMAIN}:8201/"
echo
