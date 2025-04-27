## Use the official Airflow base image
#FROM apache/airflow:latest
#
## ensure pip --user bin is on PATH
#ENV PATH="/home/airflow/.local/bin:${PATH}"
#
#USER root
## … install any system deps if needed …
#
#USER airflow
#COPY requirements.txt /
#RUN pip install --no-cache-dir -r /requirements.txt
#
## install dbt core + bigquery adapter
#RUN pip install --no-cache-dir dbt-core dbt-bigquery


FROM apache/airflow:2.10.5

# ensure pip --user bin is on PATH
ENV PATH="/home/airflow/.local/bin:${PATH}"
# point dbt at the place we're going to copy .dbt into
ENV DBT_PROFILES_DIR=/opt/airflow/dbt_project/.dbt

USER root
RUN apt-get update \
 && apt-get install -y git \
 && rm -rf /var/lib/apt/lists/*

# create the target folder for your profiles
#RUN mkdir -p /opt/airflow/dbt_project/.dbt \
#    && chown -R airflow: /opt/airflow/dbt_project

RUN mkdir -p /opt/airflow/dbt_project/.dbt \
    && mkdir -p /opt/airflow/dbt_project/target \
    && chown -R airflow: /opt/airflow/dbt_project

# copy in your requirements and install them
USER airflow
COPY requirements.txt /
RUN pip install --no-cache-dir -r /requirements.txt

# install dbt core + bigquery adapter
RUN pip install --no-cache-dir dbt-core dbt-bigquery

# now bring in your dbt profiles
# (adjust the source path to wherever your local .dbt lives)
USER root

RUN mkdir -p /opt/airflow/dbt_project/.dbt \
    && chown -R airflow: /opt/airflow/dbt_project

COPY data_pipeline_dbt/.dbt /opt/airflow/dbt_project/.dbt

RUN chown -R airflow: /opt/airflow/dbt_project/.dbt

# drop back to airflow user for runtime
USER airflow
