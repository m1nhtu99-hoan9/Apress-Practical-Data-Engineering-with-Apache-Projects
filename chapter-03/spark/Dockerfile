FROM tabulario/spark-iceberg

USER root

# Match chapter-02 notebook tooling for SQL authoring and Kotlin kernel support.
RUN pip install --no-cache-dir \
      "jupyterlab_sql_editor[all]" \
      kotlin-jupyter-kernel \
 && python3 -m kotlin_kernel fix-kernelspec-location

# Make Spark/Iceberg jars available to the Kotlin Jupyter kernel classpath.
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

classpath = jar_args.get("classPath", [])
added = 0
for spark_jar in sorted(glob.glob("/opt/spark/jars/*.jar")):
    jar_name = os.path.basename(spark_jar)
    kernel_jar_link = os.path.join(kernel_jars_dir, jar_name)
    if not os.path.exists(kernel_jar_link):
        os.symlink(spark_jar, kernel_jar_link)
    if jar_name not in classpath:
        classpath.append(jar_name)
        added += 1

jar_args["classPath"] = classpath
with open(jar_args_path, "w", encoding="utf-8") as f:
    json.dump(jar_args, f, indent=4)

print(f"Added {added} Spark/Iceberg jars to Kotlin kernel classpath")
PY

COPY spark/spark-defaults.conf /opt/spark/conf/spark-defaults.conf
COPY spark/scripts/data-init.sh /opt/spark/bin/data-init.sh
COPY page_view_sample.json /opt/bootstrap/page_view_sample.json

ENV SPARK_CONF_DIR=/opt/spark/conf

# Required when launching Spark inside Kotlin kernel (not via spark-submit/pyspark scripts).
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
-Dspark.sql.catalog.demo.warehouse=s3://warehouse/ \
-Dspark.sql.catalog.demo.s3.endpoint=http://minio:9000 \
-Dspark.sql.defaultCatalog=demo \
-Dspark.sql.catalogImplementation=in-memory"

RUN chmod u+x /opt/spark/bin/data-init.sh
