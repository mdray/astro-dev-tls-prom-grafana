from datetime import datetime,timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator, DummyOperator
from airflow.models import Variable

for n in range(10):

    with DAG(
        "simple_wide2_" + str(n).zfill(3),
        schedule_interval=timedelta(seconds=60),
        start_date=datetime(2021, 8, 1),
        catchup=False,
        max_active_tasks=2000,
        concurrency=2000,
    ):
        COUNT = int(Variable.get("COUNT"))
        for i in range(int(COUNT)):
            t = DummyOperator()


