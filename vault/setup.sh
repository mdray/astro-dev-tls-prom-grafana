#!/bin/bash

if [ -z "$AWS_ACCESS_KEY_ID" ]; then echo "Missing AWS_ACCESS_KEY_ID in environment"; FAIL=true; fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then echo "Missing AWS_SECRET_ACCESS_KEY in environment"; FAIL=true; fi
if [ -z "$AWS_DEFAULT_REGION" ]; then echo "Missing AWS_DEFAULT_REGION in environment"; FAIL=true; fi

if [ ! -z "$FAIL" ]; then 
  echo "Not configuring Vault secrets."
  exit 1
fi

export VAULT_ADDR=http://localhost:8200/
until vault status >/dev/null; do 
  echo "waiting for Vault to become available at $VAULT_ADDR"
  sleep 0.5
done

if [ -z "$VAULT_TOKEN" ]; then 
  export VAULT_TOKEN=root
fi


if [ -z "$VAULT_AWS_CREDS_TTL" ]; then 
  export VAULT_AWS_CREDS_TTL=7200s
fi

set -e

. config.env

# careful with this
vault secrets disable aws

vault secrets enable aws

vault write aws/config/root \
    access_key=$AWS_ACCESS_KEY_ID \
    secret_key=$AWS_SECRET_ACCESS_KEY \
    region=$AWS_DEFAULT_REGION

vault write aws/config/lease \
  lease=$VAULT_AWS_CREDS_TTL \
  lease_max=$VAULT_AWS_CREDS_TTL

vault write aws/roles/airflow-dev-role \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sagemaker:*",
      "Resource": "*"
    }
  ]
}
EOF

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