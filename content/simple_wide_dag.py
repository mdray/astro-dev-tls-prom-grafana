from datetime import datetime, timedelta

from airflow import DAG

from airflow.operators.bash import BashOperator


with DAG(
    "simple_wide_01",
    schedule=timedelta(minutes=5),
    start_date=datetime(2021, 8, 1),
    catchup=False,
    max_active_tasks=10,
    concurrency=10,
    default_args={
        "retries": 0,
        "owner": "jacob.martinson@astronomer.io",
    },
):

    for i in range(10):
        t = BashOperator(task_id=f"out_{i}", bash_command="sleep 30")