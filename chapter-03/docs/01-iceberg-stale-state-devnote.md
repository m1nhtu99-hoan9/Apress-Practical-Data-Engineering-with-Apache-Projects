# Devnote: Iceberg Stale Catalog State After Warehouse Reset

Date: 2026-03-06

## Summary
`CREATE TABLE IF NOT EXISTS` in Iceberg can fail with `Location does not exist` when the catalog entry exists but the metadata object has been deleted from object storage.

Observed error pattern:
- `org.apache.iceberg.exceptions.NotFoundException`
- `Location does not exist: s3://warehouse/<namespace>/<table>/metadata/00000-....metadata.json`

## Root Cause
This stack had a state-drift risk:

1. MinIO warehouse bucket could be deleted at startup by the `mc` service.
2. REST catalog metadata (SQLite) could survive independently.
3. Catalog then points to metadata locations that no longer exist in MinIO.

That creates dangling table registrations.

## Why `IF NOT EXISTS` Still Fails
Iceberg first checks the catalog.
- If table exists in catalog, it loads that table's metadata location.
- It only creates new table metadata if no catalog entry exists.

So stale catalog pointers cause read-on-open failure before create path can proceed.

## Hardening Applied
Configuration changes now reduce recurrence:

1. Warehouse initialization is idempotent by default (no automatic bucket delete).
2. Explicit opt-in reset flag: `RESET_WAREHOUSE_ON_STARTUP=true`.
3. Persistent MinIO data volume: `minio_data`.
4. Persistent REST catalog volume at `/tmp`: `rest_catalog`.
5. Startup ordering ensures `mc` initialization completes before `rest` and `spark-iceberg`.

Additionally, Spark warehouse roots were aligned:
- `spark/spark-defaults.conf`: `s3://warehouse/`
- `docker-compose.yaml` REST `CATALOG_WAREHOUSE`: `s3://warehouse/`
- `spark/Dockerfile` Kotlin JVM opts: now `s3://warehouse/` (previously `s3://warehouse/wh/`)

## Detection Checklist
Use this when DDL behaves unexpectedly:

1. Catalog has table?
   - `SHOW TABLES IN <namespace>;`
2. Metadata object exists in MinIO?
   - `mc ls -r minio/warehouse/<namespace>/<table>/metadata`
3. REST logs show missing key?
   - search for `Location does not exist` / `NoSuchKey`

If (1)=yes and (2)=no, stale catalog state is confirmed.

## Recovery Playbook
For local/dev environments:

1. Full clean reset (recommended):
   - `docker compose down -v`
   - `docker compose up -d --build`
   - re-run table creation notebook

2. Targeted cleanup (when preserving data matters):
   - drop dangling tables from catalog
   - recreate tables so fresh metadata locations are registered

## Operational Guidance
- Keep object storage lifecycle and catalog lifecycle coupled.
- Avoid deleting warehouse buckets unless catalog is reset in the same operation.
- Prefer explicit, opt-in destructive reset flags over implicit startup cleanup.
