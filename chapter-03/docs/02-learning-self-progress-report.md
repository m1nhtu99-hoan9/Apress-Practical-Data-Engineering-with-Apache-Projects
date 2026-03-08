# Learning Note: Iceberg DDL and Spark Ingestion

Date: 2026-03-06
Chapter: 03

## Summary

Full learning path from namespace creation to data loading in Iceberg completed.
DDL was executed via `notebooks/create_iceberg_tables.ipynb`, followed by two
`spark-submit` jobs that ingested data from PostgreSQL and MinIO into
`demo.bronze.pageviews`.

## Iceberg Metadata Architecture

Iceberg separates table state into four distinct, hierarchical layers:

1. **Catalog** — maps a table name to the path of its current `metadata.json`.
   Updating this pointer is the single atomic commit step. It is the source of
   truth for all readers.
2. **Metadata file** (`metadata.json`) — records the table schema, partition
   spec, sort order, and the full snapshot history.
3. **Manifest list** — one per snapshot; lists all manifest files that belong to
   that snapshot.
4. **Manifest files** — each records a set of data file paths with per-file
   statistics: row counts, column bounds, and partition values.

Every write appends new data files, generates new manifest and manifest-list
files, writes a new `metadata.json`, then atomically swaps the catalog pointer.
No existing file is ever mutated. Readers always see a consistent snapshot,
even during a concurrent write.

## DDL: Namespace and Table Creation

DDL in Iceberg is a catalog operation, not a filesystem operation.
`CREATE NAMESPACE` registers a logical container. `CREATE TABLE` generates an
initial `metadata.json` and registers its path in the catalog under that
namespace — no data files are written at this stage.

`CREATE TABLE IF NOT EXISTS` only creates new metadata if no catalog entry
exists. If an entry exists but the metadata file has been deleted from storage,
Iceberg fails on open rather than silently creating a replacement.
(See Devnote 2026-03-06 for the stale-state failure mode this causes.)

Steps executed:
1. Opened `notebooks/create_iceberg_tables.ipynb`.
2. Created namespace `demo.bronze`.
3. Created table `pageviews` with target schema.

## Ingestion: PostgreSQL → Iceberg (JDBC)

Spark reads relational rows via the JDBC source, converts them to Parquet data
files, and commits a new Iceberg snapshot.

```bash
docker compose exec spark-iceberg /opt/spark/bin/spark-submit \
  --jars /home/iceberg/pyspark/jars/postgresql-42.7.6.jar \
  /home/iceberg/pyspark/scripts/postgres_loader.py
```

The `--jars` flag supplies the JDBC driver at the executor level. Spark resolves
the Iceberg catalog via the session configuration and routes the write through
the REST catalog.

## Ingestion: MinIO → Iceberg (S3A)

Spark reads JSON files from an S3-compatible path using the `s3a://` scheme and
writes them into the Iceberg table. Two jars are required:

- `hadoop-aws-3.3.4.jar` — provides the `S3AFileSystem` implementation.
- `aws-java-sdk-bundle-1.11.1026.jar` — provides the AWS SDK that
  `S3AFileSystem` delegates to for all object-store API calls.

```bash
docker compose exec spark-iceberg /opt/spark/bin/spark-submit \
  --jars /home/iceberg/pyspark/jars/hadoop-aws-3.3.4.jar,\
/home/iceberg/pyspark/jars/aws-java-sdk-bundle-1.11.1026.jar \
  /home/iceberg/pyspark/scripts/minio_loader.py
```

MinIO presents the same HTTP API surface as S3, so the standard S3A connector
works without modification. The source path pattern was
`s3a://pageviews/event_*.json`.

## Commit Evidence

Spark stage completion and Iceberg snapshot metrics confirm a clean write:

- Stage 2 completed: `(376/376)` tasks.
- Source file read: `s3a://pageviews/event_1772789281_6036654b-3d91-4519-b999-b8cfea1b0a3b.json`.
- Snapshot committed: `1899979337736243162`.
- `addedRecords=12002`, `addedDataFiles=1`, `totalRecords=12002`.
- Exit code: `0`.

`addedDataFiles=1` means Spark coalesced output into a single partition.
`totalRecords` matching `addedRecords` confirms this was the first write to an
otherwise empty table — no prior snapshots existed.

## Key Principles

- DDL and data writes both route through the catalog — the catalog is always the
  first authority on whether a table exists.
- Each Spark write creates exactly one new immutable snapshot; prior snapshots
  remain intact and queryable via time travel.
- JDBC and S3A ingestion follow the same Iceberg commit path; only the Spark
  read-source differs.
- `addedDataFiles=1` is acceptable for a small initial load. At scale, higher
  Spark parallelism should produce multiple smaller files to improve read
  performance through better pruning.
- The `bronze` layer holds raw ingested data with no transformation — preserving
  source records exactly as received before any curation or enrichment.

## Operational Sequence (Repeatable)

1. Create namespace and table via notebook DDL — establishes the catalog entry
   and initial `metadata.json`.
2. Run JDBC `spark-submit` for relational source data (PostgreSQL).
3. Run S3A `spark-submit` for object-store event data (MinIO).
4. Validate: check stage completion counts, snapshot ID in logs, and
   `addedRecords` metric.
