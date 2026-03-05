# Learner Note: Debugging Iceberg `CREATE TABLE IF NOT EXISTS` with Missing Metadata

**Date:** 2026-03-05
**Notebook:** `notebooks/create_iceberg_tables.ipynb`

---

## Context

While running this SQL cell:

```sql
CREATE TABLE IF NOT EXISTS bronze.users (
  id BIGINT,
  first_name STRING,
  last_name STRING,
  email STRING,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
) USING iceberg
PARTITIONED BY (days(created_at))
TBLPROPERTIES (
  'format-version' = '2',
  'comment' = 'Dimension table for user information'
);
```

the following errors appeared:

- `NoSuchTableException` / `NotFoundException`
- `Location does not exist: s3://warehouse/bronze/users/metadata/00000-....metadata.json`

This is counterintuitive at first glance — the table is being *created*, so why is Iceberg already looking for a metadata file?

---

## Initial Hypothesis

The table was already registered in the Iceberg catalog, but its corresponding metadata file in MinIO/S3 was missing or had been deleted.

This causes `IF NOT EXISTS` to fail because Iceberg found the table in the catalog and immediately tried to open (not create) it — then hit a missing file.

---

## How We Verified

1. `SHOW TABLES IN bronze;` → returned `users` (catalog entry exists).
2. Inspected MinIO: `warehouse/bronze/users/metadata/` was empty (object missing).
3. `iceberg-rest` container logs showed:
   - `Location does not exist: s3://warehouse/bronze/users/metadata/...`
   - `NoSuchKey` from S3/MinIO.

**Conclusion:** This is a **dangling (orphaned) catalog registration** — the catalog points to a metadata file that no longer exists in object storage.

---

## Key Concept: Iceberg's Two-Part Table Identity

Every Iceberg table has two linked components that must stay consistent:

| Layer | What it is | Where it lives |
|---|---|---|
| **Catalog record** | Namespace + table name → pointer to current `metadata.json` location | Catalog DB (e.g., JDBC, Hive Metastore, REST catalog) |
| **Metadata file** | JSON document describing schema, partitions, snapshots, history | Object store (S3/MinIO/GCS/ADLS) |

The metadata file (`*.metadata.json`) itself is the heart of an Iceberg table. Each write operation creates a **new, immutable metadata file**, enabling time travel and ACID commits. It contains:

- Current and historical schemas (with column IDs for safe schema evolution)
- Partition specification and evolution history
- Snapshot history (each snapshot points to a manifest list → manifest files → data files)
- Current snapshot reference
- `metadata-log`: the ordered history of previous metadata file locations

### `CREATE TABLE IF NOT EXISTS` — What Actually Happens

```
1. Ask catalog: does `bronze.users` exist?
2a. YES → resolve metadata file location from catalog record
         → attempt to LOAD that metadata.json from object store   ← FAILS HERE
2b. NO  → create new metadata.json in object store
         → register the new location in catalog
```

Iceberg is not asking for a metadata file "before creating a new table." It found an existing catalog record and tried to open the table it believes already exists. The error is a symptom of **catalog–storage desynchronisation**, not a creation bug.

---

## Root Cause in This Setup

Object store data was **cleaned or reset** while the catalog database (Postgres/SQLite backing the REST catalog) was **left intact**. This produces stale catalog pointers to deleted metadata files.

An additional config path mismatch was also observed:

| Component | Configured warehouse path |
|---|---|
| Spark | `s3://warehouse/wh/` |
| REST catalog | `s3://warehouse/` |

This divergence means Spark and the REST catalog resolve table locations differently, which can cause writes to go to one path while the catalog points to another. This should be aligned to the same root.

---

## Fix / Resolution

Choose the option that fits your situation:

### Option A — Drop the orphaned catalog entry, then recreate (recommended for dev/local)

The challenge: `DROP TABLE bronze.users` will also fail because Spark tries to load the metadata before dropping it.

Use the REST catalog API directly to remove the stale entry:

```bash
# Drop via REST catalog HTTP endpoint (bypasses Spark's metadata load step)
curl -X DELETE http://localhost:8181/v1/namespaces/bronze/tables/users
```

Then recreate normally:

```sql
CREATE TABLE IF NOT EXISTS bronze.users ( ... ) USING iceberg ...;
```

### Option B — Use `spark.sql` with `invalidateCache` first (sometimes works)

```python
spark.sql("REFRESH TABLE bronze.users")   # may surface a cleaner error path
spark.sql("DROP TABLE IF EXISTS bronze.users")
```

Note: this still requires Spark to load metadata, so it may fail if the metadata file is truly gone. If it does, fall back to Option A.

### Option C — Recreate the metadata manually (advanced)

If data files are still present in the object store and you want to recover the table without data loss, you can:
1. Write a minimal `metadata.json` pointing to existing manifest files.
2. Re-register the table via the REST catalog `/register` endpoint.

This is complex and error-prone; reserve for production data recovery scenarios.

---

## Practical Debug Checklist

When `CREATE TABLE IF NOT EXISTS` (or any Iceberg table operation) throws `NoSuchTableException` or `Location does not exist`:

1. **Check catalog state:**
   ```sql
   SHOW TABLES IN <namespace>;
   ```
   If the table appears, a catalog record exists.

2. **Check object store path:**
   ```bash
   mc ls minio/warehouse/<namespace>/<table>/metadata/
   # or
   aws s3 ls s3://warehouse/<namespace>/<table>/metadata/
   ```
   If empty or missing → orphaned catalog record confirmed.

3. **Check REST catalog / engine logs** for:
   - `NoSuchKey` (S3/MinIO error — object does not exist)
   - `Location does not exist` (Iceberg REST catalog error)
   - `NoSuchTableException` (Spark/engine error)

4. **Check warehouse path alignment** — confirm Spark's `spark.sql.catalog.<name>.warehouse` matches the REST catalog's `warehouse` config exactly.

5. **If catalog exists but metadata is gone:**
   - Treat as an orphaned table state.
   - Remove the catalog entry via the REST API (Option A above).
   - Recreate the table cleanly.

---

## Why Spark Feels Like a SQL Front-End for Iceberg

When working in `%%sql` cells against an Iceberg catalog, it is easy to think of Spark as just a query interface. What is actually happening under the hood is a clear division of responsibility:

**Spark's role (compute engine):**
- Parses, plans, and executes distributed query plans
- Handles joins, shuffles, aggregations, ETL logic, UDFs
- Manages DataFrame API, Structured Streaming, broadcast variables
- Reads and writes actual Parquet/ORC data files

**Iceberg's role (table format / contract):**
- Manages schema and partition evolution (addColumn, evolve partition spec without rewrite)
- Maintains snapshots, enabling time travel (`VERSION AS OF`, `TIMESTAMP AS OF`)
- Provides ACID-style optimistic concurrency control on commits
- Defines where data files live and how they are organised (manifest lists → manifests → data files)

A useful mental model:

> **Iceberg is the contract for how table state is stored and evolved. Spark is the engine that executes work against that contract.**

The contract is engine-agnostic: the same Iceberg table can be queried by Trino, Flink, DuckDB, or Daft — each using the same metadata files, getting the same consistent view. This is precisely why the catalog and object store must stay in sync: every engine relies on the metadata chain to understand what the table looks like.

---

## Concepts to Revisit

- [ ] Iceberg metadata file chain: `metadata.json` → manifest list → manifest files → data files
- [ ] How Iceberg's optimistic concurrency works (compare-and-swap on the catalog pointer)
- [ ] `format-version = 2` vs `1` differences (row-level deletes, sequence numbers)
- [ ] `days(created_at)` partition transform and how Iceberg partition evolution works without rewrites
- [ ] REST catalog `/v1` API endpoints for table registration, deregistration, and namespace management
