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

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

COPY .pyiceberg.yaml /root/.pyiceberg.yaml

COPY entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]
CMD ["notebook"]
