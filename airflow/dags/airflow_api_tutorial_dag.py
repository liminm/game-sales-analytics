from airflow.decorators import dag, task
from datetime import datetime, timedelta

default_args = {
    "owner": "airflow",
    'retries': 5,
    'retry_delay': timedelta(minutes=5),
}


@dag(
    dag_id='dag_with_taskflow_api_v02',
    default_args=default_args,
    schedule_interval='@daily',
    start_date=datetime(2021, 1, 1),
    catchup=False
)
def hello_world_etl():

    @task(multiple_outputs=True)
    def get_name():
        return {
            'first_name': 'Jerry',
            'last_name': 'Lim'
        }

    @task()
    def get_age():
        return 28

    @task()
    def greet(first_name, last_name, age):
        message = f'Hello, {first_name} {last_name}! You are {age} years old.'
        print(message)
        return message

    name_dict = get_name()
    age = get_age()
    greet(
        first_name=name_dict["first_name"],
        last_name=name_dict["last_name"],
        age=age
    )

greet_dag = hello_world_etl()

