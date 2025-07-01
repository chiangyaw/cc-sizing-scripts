# Prisma Cloud GCP License Sizing Script

## Overview

This document describes how to prepare for, and how to run the Prisma Cloud GCP License Sizing Script.

## Prerequisites

### Required Permissions

The GCP account that is used to run the sizing script must have the required permissions to be able to collect sizing information.

### Required GCP APIs

The below GCP APIs need to be enabled in order to gather information from GCP.

* gcloud projects list
* gcloud compute instances list
* gcloud sql instances list
* gcloud storage ls
* gcloud filestore instances list
* gcloud alpha bq datasets list
* gcloud bigtable instances list
* gcloud spanner instances list
* gcloud redis instances list
* gcloud memcache instances list
* gcloud firestore databases list
* gcloud functions list
* gcloud run services list

### Verbose Mode

By default, the sizing script will run in quiet mode. If you wish to enable verbose mode, specify `verbose` as a command-line parameter

## Running the Script

Follow the steps below to run the Prisma Cloud GCP License Sizing Script.

1. Download the sizing script to your local computer
    1. [resource-count-gcp.sh](resource-count-gcp.sh)
1. Log into your GCP Console
1. Launch the GCP Cloud Shell
1. Click the Vertical Ellipsis on the right side of your GCP Console
1. Select "Upload File"
1. Upload the sizing script to your GCP Cloud Shell
1. Run the sizing script.
    1. `chmod +x resource-count-gcp.sh`
    1. `./resource-count-gcp.sh`
1. Share the results with your Palo Alto Networks team