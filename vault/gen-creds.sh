#!/bin/bash

if [ -z "$VAULT_ADDR" ]; then 
  export VAULT_ADDR=https://localhost.cosmic-security.net:8200/ 
fi

if [ -z "$VAULT_TOKEN" ]; then 
  export VAULT_TOKEN=root
fi

set -e

. config.env

echo 'vault read aws/creds/airflow-dev-role'

# Read sts token
json=`vault read -format=json aws/creds/airflow-dev-role`

# Print result
echo $json | jq

# Parse into env vars
access_key=`echo $json | jq -r .data.access_key`
secret_key=`echo $json | jq -r .data.secret_key`

astro_envfile="${ASTRODIR}/.env"

echo 
echo Adding dynamic credentials to ${astro_envfile}: 

# access key must be url encoded in airflow conn var
# https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/connections/aws.html#examples
usecret=$(printf %s "$secret_key" | jq -sRr @uri)

echo AIRFLOW_CONN_AWS_DEFAULT=aws://${access_key}:${usecret}@/region_name=${AWS_DEFAULT_REGION} >> $astro_envfile
echo AIRFLOW_CONN_AWS_SAGEMAKER=aws://${access_key}:${usecret}@/region_name=${AWS_DEFAULT_REGION} >> $astro_envfile
echo AWS_ACCESS_KEY_ID=${access_key} >> $astro_envfile
echo AWS_SECRET_ACCESS_KEY=${secret_key} >> $astro_envfile

cat $astro_envfile

echo
echo Paste this into your terminal to use:
echo
cat <<EOF
#######################################################
export HISTCONTROL=ignoreboth
export HISTIGNORE=\"history*:export*\"
  export AWS_ACCESS_KEY_ID=${access_key}
  export AWS_SECRET_ACCESS_KEY=${secret_key}
#######################################################
EOF