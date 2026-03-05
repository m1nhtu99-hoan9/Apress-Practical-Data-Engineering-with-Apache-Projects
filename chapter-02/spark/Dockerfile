ARG UV_BASE_IMAGE=ghcr.io/astral-sh/uv:python3.10-bookworm-slim
FROM ${UV_BASE_IMAGE}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      wget \
      vim \
      unzip \
      openjdk-17-jdk \
      build-essential \
      software-properties-common \
      ssh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Jupyter and other python deps
COPY requirements.txt .
RUN uv pip install --system -r requirements.txt

RUN uv pip install --system "jupyterlab_sql_editor[all]"

# Add Kotlin kernel
RUN uv pip install --system kotlin-jupyter-kernel && \
    python3 -m kotlin_kernel fix-kernelspec-location

# Add scala kernel via spylon-kernel
RUN python3 -m spylon_kernel install

# Optional env variables
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.9.7-src.zip:$PYTHONPATH

WORKDIR ${SPARK_HOME}

ENV SPARK_VERSION=3.5.8
ENV SPARK_MAJOR_VERSION=3.5
ENV ICEBERG_VERSION=1.9.0

# Download spark
RUN mkdir -p ${SPARK_HOME} \
 && wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    https://mirrors.tuna.tsinghua.edu.cn/apache/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    -O spark-${SPARK_VERSION}-bin-hadoop3.tgz \
 && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
 && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz

# Iceberg Spark runtime
RUN wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    https://maven.aliyun.com/repository/public/org/apache/iceberg/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar \
    -O /opt/spark/jars/iceberg-spark-runtime-${SPARK_MAJOR_VERSION}_2.12-${ICEBERG_VERSION}.jar

# Iceberg AWS bundle
RUN wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    https://maven.aliyun.com/repository/public/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar \
    -O /opt/spark/jars/iceberg-aws-bundle-${ICEBERG_VERSION}.jar

# Iceberg GCP bundle
RUN wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    https://maven.aliyun.com/repository/public/org/apache/iceberg/iceberg-gcp-bundle/${ICEBERG_VERSION}/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar \
    -O /opt/spark/jars/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar

# Iceberg Azure bundle
RUN wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    https://maven.aliyun.com/repository/public/org/apache/iceberg/iceberg-azure-bundle/${ICEBERG_VERSION}/iceberg-azure-bundle-${ICEBERG_VERSION}.jar \
    -O /opt/spark/jars/iceberg-azure-bundle-${ICEBERG_VERSION}.jar

# Make Spark/Iceberg jars available to the Kotlin Jupyter kernel classpath
RUN python3 - <<'PY'
import glob
import json
import os
import run_kotlin_kernel

kernel_home = os.path.dirname(run_kotlin_kernel.__file__)
kernel_jars_dir = os.path.join(kernel_home, "jars")
jar_args_path = os.path.join(kernel_home, "config", "jar_args.json")

with open(jar_args_path, "r", encoding="utf-8") as f:
    jar_args = json.load(f)

classpath = jar_args["classPath"]
added = 0
for spark_jar in sorted(glob.glob("/opt/spark/jars/*.jar")):
    jar_name = os.path.basename(spark_jar)
    kernel_jar_link = os.path.join(kernel_jars_dir, jar_name)
    if not os.path.exists(kernel_jar_link):
        os.symlink(spark_jar, kernel_jar_link)
    if jar_name not in classpath:
        classpath.append(jar_name)
        added += 1

with open(jar_args_path, "w", encoding="utf-8") as f:
    json.dump(jar_args, f, indent=4)

print(f"Added {added} Spark/Iceberg jars to Kotlin kernel classpath")
PY

# Install AWS CLI
RUN wget --progress=dot:giga --tries=5 --waitretry=3 --continue \
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -O "awscliv2.zip" \
 && unzip awscliv2.zip \
 && ./aws/install \
 && rm awscliv2.zip \
 && rm -rf aws/

RUN mkdir -p /home/iceberg/data /opt/data

COPY data/ /opt/data/
COPY scripts/data-init.sh /opt/spark/bin/data-init.sh
RUN chmod u+x /opt/spark/bin/data-init.sh

RUN mkdir -p /home/iceberg/localwarehouse /home/iceberg/notebooks /home/iceberg/warehouse /home/iceberg/spark-events /home/iceberg
COPY notebooks/ /home/iceberg/notebooks

# Add a notebook command
RUN echo '#! /bin/sh' >> /bin/notebook \
 && echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/notebook \
 && echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/notebook \
 && echo "pyspark" >> /bin/notebook \
 && chmod u+x /bin/notebook

# Add a pyspark-notebook command (alias for notebook command for backwards-compatibility)
RUN echo '#! /bin/sh' >> /bin/pyspark-notebook \
 && echo 'export PYSPARK_DRIVER_PYTHON=jupyter-notebook' >> /bin/pyspark-notebook \
 && echo "export PYSPARK_DRIVER_PYTHON_OPTS=\"--notebook-dir=/home/iceberg/notebooks --ip='*' --NotebookApp.token='' --NotebookApp.password='' --port=8888 --no-browser --allow-root\"" >> /bin/pyspark-notebook \
 && echo "pyspark" >> /bin/pyspark-notebook \
 && chmod u+x /bin/pyspark-notebook

RUN mkdir -p /root/.ipython/profile_default/startup
COPY ipython/startup/00-prettytables.py /root/.ipython/profile_default/startup
COPY ipython/startup/README /root/.ipython/profile_default/startup

COPY spark-defaults.conf /opt/spark/conf
ENV PATH="/opt/spark/sbin:/opt/spark/bin:${PATH}"
ENV SPARK_CONF_DIR="/opt/spark/conf"

# Required when launching Spark inside Kotlin kernel (not via spark-submit/pyspark scripts)
ENV KOTLIN_JUPYTER_KERNEL_EXTRA_JVM_OPTS="\
--add-opens=java.base/java.lang=ALL-UNNAMED \
--add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
--add-opens=java.base/java.lang.reflect=ALL-UNNAMED \
--add-opens=java.base/java.io=ALL-UNNAMED \
--add-opens=java.base/java.net=ALL-UNNAMED \
--add-opens=java.base/java.nio=ALL-UNNAMED \
--add-opens=java.base/java.util=ALL-UNNAMED \
--add-opens=java.base/java.util.concurrent=ALL-UNNAMED \
--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED \
--add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
--add-opens=java.base/sun.nio.cs=ALL-UNNAMED \
--add-opens=java.base/sun.security.action=ALL-UNNAMED \
--add-opens=java.base/sun.util.calendar=ALL-UNNAMED \
--add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
-Dio.netty.tryReflectionSetAccessible=true \
-Dspark.master=local[*] \
-Dspark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
-Dspark.sql.catalog.demo=org.apache.iceberg.spark.SparkCatalog \
-Dspark.sql.catalog.demo.type=rest \
-Dspark.sql.catalog.demo.uri=http://rest:8181 \
-Dspark.sql.catalog.demo.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
-Dspark.sql.catalog.demo.warehouse=s3://warehouse/wh/ \
-Dspark.sql.catalog.demo.s3.endpoint=http://minio:9000 \
-Dspark.sql.defaultCatalog=demo \
-Dspark.sql.catalogImplementation=in-memory"

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

COPY .pyiceberg.yaml /root/.pyiceberg.yaml

COPY entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]
CMD ["notebook"]
