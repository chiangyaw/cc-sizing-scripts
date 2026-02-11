# Cortex Cloud GCP License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Cortex Cloud GCP License Sizing Script.

## Prerequisites

### Required Permissions

The GCP account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required GCP APIs

The below GCP APIs need to be enabled in order to gather information from GCP.

* gcloud projects describe
* gcloud projects list
* gcloud resource-manager folders describe
* gcloud compute instances list
* gcloud sql instances list
* gcloud filestore instances list
* gcloud alpha bq datasets list
* gcloud bigtable instances list
* gcloud spanner instances list
* gcloud redis instances list
* gcloud memcache instances list
* gcloud firestore databases list
* gcloud functions list
* gcloud run services list
* gcloud storage ls
* gcloud artifacts repositories list
* gcloud artifacts docker images list

### Verbose Mode

By default, the sizing script will run in quiet mode. If you wish to enable verbose mode, specify `verbose` as a command-line parameter

## Running the Script

Follow the steps below to run the Cortex Cloud GCP License Sizing Script.

1. Download the sizing script to your local computer
    * [resource-count-gcp.sh](resource-count-gcp.sh)
2. Log into your GCP Console
3. Launch the GCP Cloud Shell
1. Click the Vertical Ellipsis on the right side of your GCP Console
4. Select "Upload File"
5. Upload the sizing script to your GCP Cloud Shell
6. Run the sizing script. Optionally, you can add `--project` or `--folder` flag with project or folder ID, so that the script only cover the specific project or folder.
    * `chmod +x resource-count-gcp.sh`
    * `./resource-count-gcp.sh`
7. Share the results with your Palo Alto Networks team
