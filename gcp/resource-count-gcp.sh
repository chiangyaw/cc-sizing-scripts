#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

# Instructions:
#
# - Go to the GCP Console
#
# - Open Cloud Shell >_
#
# - Click on three dot vertical menu on the right side (left of minimize button)
#
# - Upload this script
#
# - Make this script executable:
#   chmod +x resource-count-gcp.sh
#
# - Run this script:
#   resource-count-gcp.sh
#   resource-count-gcp.sh verbose (see below)
#
# This script may generate errors when:
#
# - The API is not enabled (and gcloud prompts you to enable the API).
# - You don't have permission to make the API calls.
#
# API/CLI used:
#
# - gcloud projects list
# - gcloud compute instances list
# - gcloud sql instances list
# - gcloud storage ls 
# - gcloud filestore instances list
# - gcloud alpha bq datasets list
# - gcloud bigtable instances list 
# - gcloud spanner instances list
# - gcloud redis instances list
# - gcloud memcache instances list
# - gcloud firestore databases list
# - gcloud artifacts repositories list
# - gcloud artifacts docker images list
##########################################################################################

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Optionally enable verbose mode by passing "verbose" as an argument.
##########################################################################################

# By default:
#
# - You will not be prompted to enable an API (we assume that you don't use the service, thus resource count is assumed to be 0).
# - When an error is encountered, you most likely don't have API access, thus resource count is assumed to be 0).

if [ "${1}X" == "verboseX" ]; then
  VERBOSITY_ARGS="--verbosity error"
else
  VERBOSITY_ARGS="--verbosity critical --quiet"
fi

##########################################################################################
## GCP Utility functions.
##########################################################################################

gcloud_projects_list() {
  RESULT=$(gcloud projects list --format json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud compute instances list --filter="status:(RUNNING)" --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_sql_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud sql instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_storage_ls() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud storage ls --project "${1}" $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_filestore_instance_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud filestore instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_alpha_bq_datasets_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud alpha bq datasets list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_bigtable_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud bigtable instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_spanner_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud spanner instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_redis_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud redis instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_memcache_instances_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud memcache instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_firestore_databases_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud firestore databases list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}
####

gcloud_functions_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud functions list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_run_services_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud run services list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_artifacts_docker_images_list() {
  # shellcheck disable=SC2086
  RESULT=$(gcloud artifacts docker images list "us-central1-docker.pkg.dev/${1}/gcr.io" --include-tags --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

get_project_list() {
  PROJECTS=($(gcloud_projects_list | jq  -r '.[].projectId'))
  TOTAL_PROJECTS=${#PROJECTS[@]}
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_project_counters() {
  COMPUTE_INSTANCES_COUNT=0
  SQL_INSTANCES_COUNT=0
  # WORKLOAD_COUNT=0
  STORAGE_COUNT=0
  FILESTORE_COUNT=0
  BIGQUERY_COUNT=0
  BIGTABLE_COUNT=0
  SPANNER_COUNT=0
  REDIS_COUNT=0
  MEMCACHE_COUNT=0
  FIRESTORE_COUNT=0
  CLOUD_FUNCTIONS_COUNT=0
  CLOUD_RUN_COUNT=0
  ACR_IMAGES_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  SQL_INSTANCES_COUNT_GLOBAL=0
  # WORKLOAD_COUNT_GLOBAL=0
  STORAGE_COUNT_GLOBAL=0
  FILESTORE_COUNT_GLOBAL=0
  BIGQUERY_COUNT_GLOBAL=0
  BIGTABLE_COUNT_GLOBAL=0
  SPANNER_COUNT_GLOBAL=0
  REDIS_COUNT_GLOBAL=0
  MEMCACHE_COUNT_GLOBAL=0
  FIRESTORE_COUNT_GLOBAL=0
  CLOUD_FUNCTIONS_COUNT_GLOBAL=0
  CLOUD_RUN_COUNT_GLOBAL=0
  ACR_IMAGES_COUNT_GLOBAL=0
}

##########################################################################################
## Iterate through the projects, and billable resource types.
##########################################################################################

count_project_resources() {
  for ((PROJECT_INDEX=0; PROJECT_INDEX<=(TOTAL_PROJECTS-1); PROJECT_INDEX++))
  do
    PROJECT="${PROJECTS[$PROJECT_INDEX]}"

    echo "###################################################################################"
    echo "Processing Project: ${PROJECT}"

    RESOURCE_COUNT=$(gcloud_compute_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of Running Compute Instances: ${COMPUTE_INSTANCES_COUNT}"

    RESOURCE_COUNT=$(gcloud_sql_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    SQL_INSTANCES_COUNT=$((SQL_INSTANCES_COUNT + RESOURCE_COUNT))
    echo "  Count of SQL Instances: ${SQL_INSTANCES_COUNT}"

    RESOURCE_COUNT=$(gcloud_storage_ls "${PROJECT}" | wc -l)
    STORAGE_COUNT=$((STORAGE_COUNT + RESOURCE_COUNT))
    echo "  Count of Storage Buckets: ${STORAGE_COUNT}"

    RESOURCE_COUNT=$(gcloud_filestore_instance_list "${PROJECT}" | jq '.[].name' | wc -l)
    FILESTORE_COUNT=$((FILESTORE_COUNT + RESOURCE_COUNT))
    echo "  Count of Filestore: ${FILESTORE_COUNT}"

    RESOURCE_COUNT=$(gcloud_alpha_bq_datasets_list "${PROJECT}" | jq '.[].name' | wc -l)
    BIGQUERY_COUNT=$((BIGQUERY_COUNT + RESOURCE_COUNT))
    echo "  Count of BigQuery: ${BIGQUERY_COUNT}"

    RESOURCE_COUNT=$(gcloud_bigtable_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    BIGTABLE_COUNT=$((BIGTABLE_COUNT + RESOURCE_COUNT))
    echo "  Count of BigTable: ${BIGTABLE_COUNT}"

    RESOURCE_COUNT=$(gcloud_spanner_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    SPANNER_COUNT=$((SPANNER_COUNT + RESOURCE_COUNT))
    echo "  Count of Spanner: ${SPANNER_COUNT}"

    RESOURCE_COUNT=$(gcloud_redis_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    REDIS_COUNT=$((REDIS_COUNT + RESOURCE_COUNT))
    echo "  Count of Redis: ${REDIS_COUNT}"

    RESOURCE_COUNT=$(gcloud_memcache_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    MEMCACHE_COUNT=$((MEMCACHE_COUNT + RESOURCE_COUNT))
    echo "  Count of Memcache: ${MEMCACHE_COUNT}"

    RESOURCE_COUNT=$(gcloud_firestore_databases_list "${PROJECT}" | jq '.[].name' | wc -l)
    FIRESTORE_COUNT=$((FIRESTORE_COUNT + RESOURCE_COUNT))
    echo "  Count of Firestore: ${FIRESTORE_COUNT}"

    RESOURCE_COUNT=$(gcloud_functions_list "${PROJECT}" | jq '.[].name' | wc -l)
    CLOUD_FUNCTIONS_COUNT=$((CLOUD_FUNCTIONS_COUNT + RESOURCE_COUNT))
    echo "  Count of Cloud Functions: ${CLOUD_FUNCTIONS_COUNT}"

    RESOURCE_COUNT=$(gcloud_run_services_list "${PROJECT}" | jq '.[].name' | wc -l)
    CLOUD_RUN_COUNT=$((CLOUD_RUN_COUNT + RESOURCE_COUNT))
    echo "  Count of Cloud Run Services: ${CLOUD_RUN_COUNT}"

    RESOURCE_COUNT=$(gcloud_artifacts_docker_images_list "${PROJECT}" | jq '.[].name' | wc -l)
    ACR_IMAGES_COUNT=$((ACR_IMAGES_COUNT + RESOURCE_COUNT))
    echo "  Count of Artifact Registry Images: ${ACR_IMAGES_COUNT}"

    # WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + SQL_INSTANCES_COUNT + STORAGE_COUNT + FILESTORE_COUNT + BIGQUERY_COUNT + BIGTABLE_COUNT + SPANNER_COUNT + REDIS_COUNT + MEMCACHE_COUNT + FIRESTORE_COUNT))
    # echo "Total billable resources for Project ${PROJECTS[$PROJECT_INDEX]}: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    SQL_INSTANCES_COUNT_GLOBAL=$((SQL_INSTANCES_COUNT_GLOBAL + SQL_INSTANCES_COUNT))
    STORAGE_COUNT_GLOBAL=$((STORAGE_COUNT_GLOBAL + STORAGE_COUNT))
    FILESTORE_COUNT_GLOBAL=$((FILESTORE_COUNT_GLOBAL + FILESTORE_COUNT))
    BIGQUERY_COUNT_GLOBAL=$((BIGQUERY_COUNT_GLOBAL + BIGQUERY_COUNT))
    BIGTABLE_COUNT_GLOBAL=$((BIGTABLE_COUNT_GLOBAL + BIGTABLE_COUNT))
    SPANNER_COUNT_GLOBAL=$((SPANNER_COUNT_GLOBAL + SPANNER_COUNT))
    REDIS_COUNT_GLOBAL=$((REDIS_COUNT_GLOBAL + REDIS_COUNT))
    MEMCACHE_COUNT_GLOBAL=$((MEMCACHE_COUNT_GLOBAL + MEMCACHE_COUNT))
    FIRESTORE_COUNT_GLOBAL=$((FIRESTORE_COUNT_GLOBAL + FIRESTORE_COUNT))
    CLOUD_FUNCTIONS_COUNT_GLOBAL=$((CLOUD_FUNCTIONS_COUNT_GLOBAL + CLOUD_FUNCTIONS_COUNT))
    CLOUD_RUN_COUNT_GLOBAL=$((CLOUD_RUN_COUNT_GLOBAL + CLOUD_RUN_COUNT))
    ACR_IMAGES_COUNT_GLOBAL=$((ACR_IMAGES_COUNT_GLOBAL + ACR_IMAGES_COUNT))

    reset_project_counters
  done

  echo "###################################################################################"
  echo "Totals for all projects"
  echo "  Count of Running Compute Instances: ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of SQL Instances: ${SQL_INSTANCES_COUNT_GLOBAL}"
  echo "  Count of Storage Buckets: ${STORAGE_COUNT_GLOBAL}"
  echo "  Count of Filestore: ${FILESTORE_COUNT_GLOBAL}"
  echo "  Count of BigQuery: ${BIGQUERY_COUNT_GLOBAL}"
  echo "  Count of BigTable: ${BIGTABLE_COUNT_GLOBAL}"
  echo "  Count of Spanner: ${SPANNER_COUNT_GLOBAL}"
  echo "  Count of Redis: ${REDIS_COUNT_GLOBAL}"
  echo "  Count of Memcache: ${MEMCACHE_COUNT_GLOBAL}"
  echo "  Count of Firestore: ${FIRESTORE_COUNT_GLOBAL}"
  echo "  Count of Cloud Functions: ${CLOUD_FUNCTIONS_COUNT_GLOBAL}"
  echo "  Count of Cloud Run Services: ${CLOUD_RUN_COUNT_GLOBAL}"
  echo "  Count of Artifact Registry Images: ${ACR_IMAGES_COUNT_GLOBAL}"

  # WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + SQL_INSTANCES_COUNT_GLOBAL + STORAGE_COUNT_GLOBAL + FILESTORE_COUNT_GLOBAL + BIGQUERY_COUNT_GLOBAL + BIGTABLE_COUNT_GLOBAL + SPANNER_COUNT_GLOBAL + REDIS_COUNT_GLOBAL + MEMCACHE_COUNT_GLOBAL + FIRESTORE_COUNT_GLOBAL))
  # echo "Total billable resources for all projects: ${WORKLOAD_COUNT_GLOBAL}"
  echo "###################################################################################"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

get_project_list
reset_project_counters
reset_global_counters
count_project_resources
