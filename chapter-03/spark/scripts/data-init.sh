#!/bin/bash
set -euo pipefail

TARGET_DATA_DIR="/home/iceberg/data"
BOOTSTRAP_SAMPLE="/opt/bootstrap/page_view_sample.json"
TARGET_SAMPLE="${TARGET_DATA_DIR}/page_view_sample.json"

mkdir -p "${TARGET_DATA_DIR}"

if [ -s "${TARGET_SAMPLE}" ]; then
  echo "Found page_view_sample.json in ${TARGET_DATA_DIR}; skipping copy."
elif [ -f "${BOOTSTRAP_SAMPLE}" ]; then
  echo "Copying page_view_sample.json into shared data volume."
  cp "${BOOTSTRAP_SAMPLE}" "${TARGET_SAMPLE}"
else
  echo "No bundled page_view_sample.json found at ${BOOTSTRAP_SAMPLE}; skipping copy."
fi

echo "Data initialization completed."
