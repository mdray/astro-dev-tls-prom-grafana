from airflow import DAG
from airflow.operators.bash_operator import BashOperator
from datetime import datetime, timedelta

with DAG(
        "backup_metadb_b2",
        schedule_interval=timedelta(hours=1),
        start_date=datetime(2021, 8, 1),
        catchup=False,
        max_active_tasks=1,
        concurrency=1,
    ):
    dump_db = BashOperator(
        task_id='dump_db',
        bash_command='scripts/backup_metadb.sh',
        # bash_command='echo test',

    )