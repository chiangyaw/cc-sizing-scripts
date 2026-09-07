# Cortex Cloud Azure License Sizing Script

## Overview

This document describes how to prepare for and run the Cortex Cloud Azure License Sizing Script.

## Prerequisites

### Required Tools

* `python3`
* `jq` (**required** — used to sum AKS node counts)
* `az` (Azure CLI)

> Azure Cloud Shell (Bash) already includes all of the above, so no installation is needed there.

### Required Permissions

The Azure account that is used to run the sizing script must have the required permissions (e.g. **Reader**) on every subscription you want to include, so it can collect sizing information.

### Required Azure APIs

The Azure CLI commands below are used to gather information from Azure:

* `az account list`
* `az account show`
* `az resource list`
* `az vm list`
* `az aks list`

## Running the Script

Follow the steps below to run the script.

1. Download the sizing script to your local computer
    1. [resource-count-azure.py](resource-count-azure.py)
1. Log into your Azure Console
1. Launch Azure Cloud Shell
1. Select "Bash" as your shell in your Azure Console
1. Click the "Upload/Download Files" button to upload the sizing script
1. Run the sizing script (see options below)
1. Share the results with your Palo Alto Networks team

### Command Options

```bash
# Count ALL accessible subscriptions in the tenant (default).
# Refreshes the subscription cache first so newly granted subscriptions are included.
python3 resource-count-azure.py

# Count only the currently active subscription.
python3 resource-count-azure.py --current

# Count one specific subscription (by ID or name).
python3 resource-count-azure.py -s <SUBSCRIPTION_ID>

# Count several specific subscriptions (repeat the flag).
python3 resource-count-azure.py -s <SUBSCRIPTION_ID> -s <SUBSCRIPTION_ID>

# Skip the subscription cache refresh (faster; use if --refresh prompts for re-auth).
python3 resource-count-azure.py --no-refresh
```

| Option | Description |
|--------|-------------|
| _(none)_ | Count all subscriptions accessible to the signed-in identity. |
| `-s`, `--subscription <ID\|name>` | Scope the count to a specific subscription. Repeat to include several. |
| `--current` | Count only the currently active subscription (`az account show`). |
| `--no-refresh` | Skip `az account list --refresh`. By default the cache is refreshed so newly granted subscriptions/tenants are picked up. |
| `-h`, `--help` | Show usage. |

## Output

The script prints a per-subscription resource census, grand totals across all counted
subscriptions, and a **Cortex Cloud Licensing Summary** that maps the raw counts onto the
billable "Protected workloads" categories. In that summary:

* Standalone VMs and AKS nodes are combined into the billable **VMs** total (AKS nodes are
  "VMs running containers" and are not returned by `az vm list`).
* Serverless Functions are reported for reference only — they are **not** a billable Cortex
  Cloud workload type.

## Notes

* Subscriptions in `Enabled`, `Warned`, or `PastDue` states are counted (they are still
  active/billable). Only `Disabled`/`Deleted`/`Expired` subscriptions are skipped.
* `Container Hosts (AKS Clusters)` reports the total potential node count — the sum of
  `maxCount` (for autoscaling node pools) or `count` (for manually scaled pools) across all
  agent pool profiles of every AKS cluster.
* `Container Registries (ACR)` counts the number of registries found, not the total number of
  container images, due to Azure API limitations.
