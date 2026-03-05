# Dev Log

Date: 2026-03-05  
Scope: SQL syntax highlighting behavior in Kotlin Jupyter notebooks (`chapter-02`)

## Observation

- SQL in Kotlin triple-quoted strings (`"""..."""`) is not syntax-highlighted in JupyterLab.
- The toolbar already shows `Format SQL`, which indicates `jupyterlab_sql_editor` is present in the image.

## Current Image State

- `jupyterlab_sql_editor` is installed in [`spark/Dockerfile`](../spark/Dockerfile).
- This provides SQL formatting and SQL tooling integration, but does not make JupyterLab parse Kotlin string literals as SQL.

## Root Cause

- JupyterLab highlights per cell language mode.
- Kotlin cells stay in Kotlin mode, and there is no Kotlin-specific SQL-in-string highlighter wired in this stack.
- This is separate from Spark runtime/classpath setup; Spark can run correctly while SQL-in-string highlighting is still absent.

## Practical Workflow

1. Keep SQL in dedicated Kotlin variables and execute with `spark.sql(query)`.
2. Use the `Format SQL` toolbar action for readability.
3. For heavy SQL authoring, prototype in a SQL-native/Python `%%sql` workflow, then move the final query back into Kotlin.

## Repo Patch Applied

- Added a standard markdown guidance cell to all Kotlin notebooks in `spark/notebooks`:
  - `Iceberg - Berlin Buzzwords 2023.ipynb`
  - `Iceberg - Getting Started.ipynb`
  - `Iceberg - Integrated Audits Demo.ipynb`
  - `Iceberg - View Support.ipynb`
  - `Iceberg - Write-Audit-Publish (WAP) with Branches.ipynb`
  - `PyIceberg - Commits.ipynb`
  - `PyIceberg - Getting Started.ipynb`
  - `PyIceberg - Write support.ipynb`
- The added cell explains the limitation and shows the recommended Kotlin `query` variable pattern.

## Example Cell Pattern

```kotlin
//language=SQL
val query = """
    SELECT
        VendorID,
        tpep_pickup_datetime,
        tpep_dropoff_datetime,
        fare
    FROM nyc.taxis
""".trimIndent()

spark.sql(query).show()
```

## Decision

- No additional Docker/kernel config change is applied for this item.
- Limitation is now documented both in this dev log and in-notebook to avoid confusion with dependency/runtime issues.
