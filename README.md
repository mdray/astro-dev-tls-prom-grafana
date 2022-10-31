# Astro Dev TLS-Prom-Grafana

This repo starts an Astro dev environment and adds the following:
- Astronomer statsd exporter with Airflow to Prometheus mappings
- Prometheus
- Grafana with a dashboard covering >90% of Airflow metrics
- Nginx TLS reverse proxy (if you provide a certificate and key)

# Dashboard Examples

![Scaling Dashboard](img/scaling.png?raw=true "Scaling Dashboard")
![Metrics Big List](img/big-list.png?raw=true "Metrics Big List")
![Diagram](img/airflow-prometheus-2022-10-24-1120.png?raw=true "Diagram")



# Instructions 

## TLS Setup (if desired)

Create an /etc/hosts (c:/windows/system32/drivers/etc/hosts) entry for localhost on a domain you own. Example:

```
127.0.0.1 localhost.cosmic-security.net localhost
```
This will allow your browser to trust the certificate running on Docker's localhost containers.

Add your certificate and private key in PEM format to:

```
nginx/fullchain.pem
nginx/privkey.pem
```

Edit the URLs at the end of `repave.sh` to match the DNS name you setup to access your local containers, which should match your certificate subject.

## Start

WARNING: Read this script before running it. It tries to just delete containers it created but it might do more than that if there are bugs. 

It will create a new Astro dev project, then add the statsd, prometheus, grafana, and nginx+tls containers.

```./repave.sh```

This will init and start an Astro dev environment, add the metrics containers, then restart Astro dev (required to for statsd name resolution). Wait for the script to complete. If you have a filesystem symlink from `www-browser` to your web browser executable, you should see new tabs open for multiple Docker services:

Astro: http://localhost:8080/ 

Astro TLS: https://localhost.your-domain:8443/

Grafana: http://localhost:3000/

Grafana TLS: https://localhost.your-domain:3443/

## Login

Logins to Astro and Grafana are both admin:admin.

Enable the 3 example DAGs in the Airflow UI. Airflow will start sending metrics onces DAGs start running on a schedule. Most of the Grafana dashboards won't populate until metrics begin to arrive.

Feel free to open a github issue or slack me if you notice any problems.

Enjoy!

