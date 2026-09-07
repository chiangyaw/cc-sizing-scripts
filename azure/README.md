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

## Running the Script from Azure Cloud Shell

Azure Cloud Shell already has `python3`, `jq`, `az`, and `git` prepared, which makes it the easiest place to run the script.

1. Log into the [Azure Portal](https://portal.azure.com)
1. Launch **Azure Cloud Shell** and select **Bash** as the shell
1. Clone this repository and change into the Azure directory:
   ```bash
   git clone https://github.com/chiangyaw/cc-sizing-scripts.git
   cd cc-sizing-scripts/azure
   ```
1. Run the sizing script (see options below)
1. Share the results with your Palo Alto Networks team

> Alternatively, you can download [resource-count-azure.py](resource-count-azure.py) and use the Cloud Shell "Upload/Download Files" button instead of `git clone`.

## Counting an Entire Azure Tenant

By default (no arguments) the script counts **every subscription the signed-in identity can access**, which is how you size a whole tenant:

```bash
python3 resource-count-azure.py
```

For this to truly cover the entire tenant, keep the following in mind:

- **Permissions:** The signed-in identity must have at least **Reader** on every subscription you want counted. Subscriptions the identity cannot see are not returned by `az account list` and therefore cannot be counted. For tenant-wide coverage, use an account with Reader assigned at the **root management group** (or use [elevated access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin) to assign it).
- **Cache refresh:** The script runs `az account list --refresh` by default so subscriptions granted after your last `az login` are included. Use `--no-refresh` only if the refresh prompts for interactive re-authentication.
- **Subscription states:** Subscriptions in `Enabled`, `Warned`, or `PastDue` states are all counted (they remain billable). Only `Disabled`/`Deleted`/`Expired` subscriptions are skipped.
- **Scope note:** The script enumerates subscriptions directly; it does not traverse management groups. Coverage is therefore determined by the RBAC of the signed-in identity, not by management-group hierarchy.

To confirm which subscriptions will be counted before running, list them with:

```bash
az account list --all --refresh --output table
```

## Command Options

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
