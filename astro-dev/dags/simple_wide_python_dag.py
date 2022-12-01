from datetime import datetime,timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.dummy_operator import DummyOperator
from airflow.models import Variable
from airflow.decorators import dag, task # DAG and task decorators for interfacing with the TaskFlow API


for n in range(5):
    with DAG(
        "simple_wide_python_" + str(n).zfill(3),
        schedule_interval=timedelta(seconds=60),
        start_date=datetime(2021, 8, 1),
        catchup=False,
        max_active_tasks=2000,
        concurrency=2000,
    ):
        COUNT = int(Variable.get("COUNT_PYTHON"))
        for i in range(int(COUNT)):
            @task(task_id="python_" + str(n).zfill(3))
            def return_val(ds=None, **kwargs):
                """Print the Airflow context and ds variable from the context."""
                pprint(kwargs)
                print(ds)
                return task_id

