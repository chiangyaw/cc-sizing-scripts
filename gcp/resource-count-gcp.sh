#!/bin/bash

# shellcheck disable=SC2102,SC2181,SC2207

if ! type "jq" > /dev/null; then
  echo "Error: jq is required."
  exit 1
fi

USAGE="Usage: $0 [--project PROJECT_ID] [--folder FOLDER_ID] [--verbose]"
VERBOSE=false
SCAN_PROJECT=""
SCAN_FOLDER=""

# Manual argument parsing for long options
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      SCAN_PROJECT="$2"
      shift 2
      ;;
    --folder)
      SCAN_FOLDER="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "$USAGE"
      exit 1
      ;;
  esac
done

if [ "$VERBOSE" = true ]; then
  VERBOSITY_ARGS="--verbosity error"
else
  VERBOSITY_ARGS="--verbosity critical --quiet"
fi

# Validation Logic
if [ -n "$SCAN_PROJECT" ]; then
    if ! gcloud projects describe "$SCAN_PROJECT" &>/dev/null; then
        echo "Error: Project '$SCAN_PROJECT' not found or you lack permissions."
        exit 1
    fi
    PROJECTS=("$SCAN_PROJECT")
elif [ -n "$SCAN_FOLDER" ]; then
    if ! gcloud resource-manager folders describe "$SCAN_FOLDER" &>/dev/null; then
        echo "Error: Folder '$SCAN_FOLDER' not found or you lack permissions."
        exit 1
    fi
    echo "Fetching projects in folder $SCAN_FOLDER..."
    PROJECTS=($(gcloud projects list --filter="parent.id=$SCAN_FOLDER" --format="value(projectId)"))
else
    echo "Fetching all accessible projects..."
    PROJECTS=($(gcloud projects list --format="value(projectId)"))
fi

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "Error: No projects found to scan."
    exit 1
fi

RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

##########################################################################################
## Worker Function
##########################################################################################

process_project_parallel() {
    local PJ=$1
    local OUT_FILE="$RESULT_DIR/$PJ.results"
    
    # Resource Counting
    local C_COMPUTE=$(gcloud compute instances list --filter="status:(RUNNING)" --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_SQL=$(gcloud sql instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_FILER=$(gcloud filestore instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_BQ=$(gcloud alpha bq datasets list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_BT=$(gcloud bigtable instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_SPANNER=$(gcloud spanner instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_REDIS=$(gcloud redis instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_MEMCACHE=$(gcloud memcache instances list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_FIRESTORE=$(gcloud firestore databases list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_FUNCTIONS=$(gcloud functions list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_RUN=$(gcloud run services list --project "$PJ" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
    local C_STORAGE=$(gcloud storage ls --project "$PJ" $VERBOSITY_ARGS 2>/dev/null | wc -l)

    # Artifact Registry Logic
    local C_ARTIFACTS=0
    local REPOS=$(gcloud artifacts repositories list --project "$PJ" --format="value(name,location,format)" $VERBOSITY_ARGS 2>/dev/null)
    while read -r REPO_LINE; do
        [ -z "$REPO_LINE" ] && continue
        local R_NAME=$(echo "$REPO_LINE" | awk '{print $1}')
        local R_LOC=$(echo "$REPO_LINE" | awk '{print $2}')
        local R_FMT=$(echo "$REPO_LINE" | awk '{print $3}')
        
        if [ "$R_FMT" == "DOCKER" ]; then
            local IMG_COUNT=$(gcloud artifacts docker images list "$R_LOC-docker.pkg.dev/$PJ/$R_NAME" --format json $VERBOSITY_ARGS 2>/dev/null | jq '. | length')
            C_ARTIFACTS=$((C_ARTIFACTS + IMG_COUNT))
        fi
    done <<< "$REPOS"

    # Export metrics as a single line for easy reading
    echo "COMPUTE=$C_COMPUTE;SQL=$C_SQL;STORAGE=$C_STORAGE;FILER=$C_FILER;BQ=$C_BQ;BT=$C_BT;SPANNER=$C_SPANNER;REDIS=$C_REDIS;MEM=$C_MEMCACHE;FS=$C_FIRESTORE;FUNC=$C_FUNCTIONS;RUN=$C_RUN;ART=$C_ARTIFACTS" > "$OUT_FILE"
    
    echo "[DONE] Finished Project: $PJ"
}

##########################################################################################
## Main Execution
##########################################################################################

echo "Starting parallel scan of ${#PROJECTS[@]} projects..."

for PROJECT in "${PROJECTS[@]}"; do
    process_project_parallel "$PROJECT" &
    # Limit to 10 parallel jobs to avoid Cloud Shell/API throttling
    while [ $(jobs -r | wc -l) -ge 10 ]; do sleep 1; done
done
wait

# Aggregate Results
G_COMPUTE=0; G_SQL=0; G_STORAGE=0; G_FILER=0; G_BQ=0; G_BT=0; G_SPANNER=0; G_REDIS=0; G_MEM=0; G_FS=0; G_FUNC=0; G_RUN=0; G_ART=0

for f in "$RESULT_DIR"/*.results; do
    [ -e "$f" ] || continue
    IFS=';' read -r C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13 < "$f"
    eval "$C1"; eval "$C2"; eval "$C3"; eval "$C4"; eval "$C5"; eval "$C6"; eval "$C7"; eval "$C8"; eval "$C9"; eval "$C10"; eval "$C11"; eval "$C12"; eval "$C13"
    
    G_COMPUTE=$((G_COMPUTE + COMPUTE)); G_SQL=$((G_SQL + SQL)); G_STORAGE=$((G_STORAGE + STORAGE))
    G_FILER=$((G_FILER + FILER)); G_BQ=$((G_BQ + BQ)); G_BT=$((G_BT + BT))
    G_SPANNER=$((G_SPANNER + SPANNER)); G_REDIS=$((G_REDIS + REDIS)); G_MEM=$((G_MEM + MEM))
    G_FS=$((G_FS + FS)); G_FUNC=$((G_FUNC + FUNC)); G_RUN=$((G_RUN + RUN)); G_ART=$((G_ART + ART))
done

# Calculate Grand Total
GRAND_TOTAL=$((G_COMPUTE + G_SQL + G_STORAGE + G_FILER + G_BQ + G_BT + G_SPANNER + G_REDIS + G_MEM + G_FS + G_FUNC + G_RUN + G_ART))

echo "-------------------------------------------------------"
echo "DETAILED RESOURCE COUNT"
echo "-------------------------------------------------------"
printf "Compute (Running): %d\nSQL Instances:     %d\nStorage Buckets:   %d\nFilestore:         %d\nBigQuery Datasets: %d\nBigTable:          %d\nSpanner:           %d\nRedis:             %d\nMemcache:          %d\nFirestore:         %d\nCloud Functions:   %d\nCloud Run:         %d\nArtifact Images:   %d\n" \
$G_COMPUTE $G_SQL $G_STORAGE $G_FILER $G_BQ $G_BT $G_SPANNER $G_REDIS $G_MEM $G_FS $G_FUNC $G_RUN $G_ART
echo "-------------------------------------------------------"
echo "GRAND TOTAL OF ALL RESOURCES: $GRAND_TOTAL"
echo "-------------------------------------------------------"