from datetime import datetime, timedelta

from airflow import DAG

from airflow.operators.bash import BashOperator


with DAG(
    "simple_wide_01",
    schedule=timedelta(minutes=1),
    start_date=datetime(2021, 8, 1),
    catchup=False,
    max_active_tasks=10,
    concurrency=10,
):

    for i in range(5):
        t = BashOperator(task_id=f"out_{i}", bash_command="sleep 5")
