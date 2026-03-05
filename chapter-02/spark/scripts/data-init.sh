#!/bin/bash
set -euo pipefail

LOCAL_DATA_DIR="/opt/data"
TARGET_DATA_DIR="/home/iceberg/data"

mkdir -p "${TARGET_DATA_DIR}"

download_or_copy_file() {
  local filename="$1"
  local url="$2"
  local local_path="${LOCAL_DATA_DIR}/${filename}"
  local target_path="${TARGET_DATA_DIR}/${filename}"
  local tmp_path="${TARGET_DATA_DIR}/${filename}.part"

  if [ -s "${target_path}" ]; then
    echo "Found ${filename} in ${TARGET_DATA_DIR}; skipping."
    return
  fi

  if [ -f "${target_path}" ]; then
    echo "Removing empty ${filename} in ${TARGET_DATA_DIR}."
    rm -f "${target_path}"
  fi

  if [ -f "${local_path}" ]; then
    echo "Copying ${filename} from ${LOCAL_DATA_DIR}."
    cp "${local_path}" "${target_path}"
    return
  fi

  echo "Downloading ${filename}."
  rm -f "${tmp_path}"
  wget --progress=dot:giga --tries=5 --waitretry=3 --continue "${url}" -O "${tmp_path}"
  mv "${tmp_path}" "${target_path}"
}

copy_or_download_film_permits_json() {
  local filename="film_permits.json"
  local local_path="${LOCAL_DATA_DIR}/${filename}"
  local target_path="${TARGET_DATA_DIR}/${filename}"
  local tmp_path="${TARGET_DATA_DIR}/${filename}.part"

  if [ -s "${target_path}" ]; then
    echo "Found ${filename} in ${TARGET_DATA_DIR}; skipping."
    return
  fi

  if [ -f "${target_path}" ]; then
    echo "Removing empty ${filename} in ${TARGET_DATA_DIR}."
    rm -f "${target_path}"
  fi

  if [ -f "${local_path}" ]; then
    echo "Copying ${filename} from ${LOCAL_DATA_DIR}."
    cp "${local_path}" "${target_path}"
    return
  fi

  echo "Downloading ${filename}."
  rm -f "${tmp_path}"
  if ! (
    cd "${TARGET_DATA_DIR}"
    wget --output-document=film_permits.json.part \
      --timeout=300 \
      --tries=3 \
      "https://data.cityofnewyork.us/api/views/tg4x-b46p/rows.json?accessType=DOWNLOAD"
  ); then
    rm -f "${tmp_path}" "${target_path}"
    echo "Error: failed to download ${filename}. Add ${filename} to spark/data to skip remote download." >&2
    return 1
  fi
  mv "${tmp_path}" "${target_path}"
}

copy_or_download_film_permits_json

download_or_copy_file "yellow_tripdata_2022-04.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-04.parquet"
download_or_copy_file "yellow_tripdata_2022-03.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-03.parquet"
download_or_copy_file "yellow_tripdata_2022-02.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-02.parquet"
download_or_copy_file "yellow_tripdata_2022-01.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2022-01.parquet"
download_or_copy_file "yellow_tripdata_2021-12.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-12.parquet"
download_or_copy_file "yellow_tripdata_2021-11.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-11.parquet"
download_or_copy_file "yellow_tripdata_2021-10.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-10.parquet"
download_or_copy_file "yellow_tripdata_2021-09.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-09.parquet"
download_or_copy_file "yellow_tripdata_2021-08.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-08.parquet"
download_or_copy_file "yellow_tripdata_2021-07.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-07.parquet"
download_or_copy_file "yellow_tripdata_2021-06.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-06.parquet"
download_or_copy_file "yellow_tripdata_2021-05.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-05.parquet"
download_or_copy_file "yellow_tripdata_2021-04.parquet" "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2021-04.parquet"
echo "Data initialization completed."
