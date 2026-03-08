# Devnote: `INSERT_COLUMN_ARITY_MISMATCH` on `silver.purchases_enriched`

**Date:** 2026-03-06
**Component:** `spark/scripts/bronze_to_silver_transformer.py`

## Summary

`overwritePartitions()` into `silver.purchases_enriched` failed because the
transformer produced two derived columns, `purchase_date` and `purchase_hour`,
but some local environments still had an older 11-column table definition in
the Iceberg catalogue.

This was a deterministic schema drift problem rather than a data-quality
problem. The write to `silver.items` committed successfully, then Spark
rejected the `silver.purchases_enriched` write during analysis before any new
snapshot was created for that table.

## What caused the mismatch

The chapter had two competing schema definitions:

- [`iceberg-schema.sql`](../iceberg-schema.sql)
  already defined `purchase_date` and `purchase_hour`.
- [`notebooks/create_iceberg_tables.ipynb`](../notebooks/create_iceberg_tables.ipynb)
  still created `silver.purchases_enriched` without those columns.

If a learner created the table from the notebook first, the catalogue kept the
older schema. When the transformer later selected 13 columns and attempted
`overwritePartitions()`, Iceberg enforced strict column arity and rejected the
write.

## Resolution

The fix has two parts.

First, the notebook DDL was updated so the documented table definition matches
the transformer output and the SQL file.

Second, the transformer now performs an idempotent schema check before writing
to `silver.purchases_enriched`. If the live table is missing
`purchase_date` or `purchase_hour`, it runs:

```sql
ALTER TABLE silver.purchases_enriched
ADD COLUMNS (purchase_date DATE, purchase_hour INT)
```

only for the columns that are absent. This keeps older local environments
recoverable without requiring a destructive warehouse reset.

## Takeaway

In an Iceberg workflow, the table schema in notebooks, bootstrap SQL, and
transformation code must stay aligned. Even when the transformation logic is
correct, an older catalogue entry can make the next write fail immediately.

For local chapter work, a small idempotent schema-reconciliation step is often
worth adding because it makes iterative learning safer and easier to debug.
