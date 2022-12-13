from datetime import datetime,timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.dummy_operator import DummyOperator
from airflow.models import Variable
from airflow.decorators import dag, task # DAG and task decorators for interfacing with the TaskFlow API

from astronomer.providers.snowflake.operators.snowflake import SnowflakeOperatorAsync

DAG_COUNT = int(Variable.get("COUNT"))

for n in range(DAG_COUNT):
    with DAG(
        "snowflake_async_wide" + str(n).zfill(3),
        schedule_interval=timedelta(seconds=60),
        start_date=datetime(2021, 8, 1),
        catchup=False,
        max_active_tasks=2000,
        concurrency=2000,
    ):
        COUNT = int(Variable.get("COUNT_SNOWFLAKE"))
        parent = None
        for i in range(int(COUNT)):

            snowflake_task  = SnowflakeOperatorAsync(
                task_id= "snowflake" + str(i).zfill(3),
                sql= "call system$wait(60, 'SECONDS')",
                trigger_rule= "one_success"
            )

snowflake_task
