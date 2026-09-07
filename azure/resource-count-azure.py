##########################################
# Azure Subscription Resource Count
#
# Prerequisites: jq (REQUIRED)
#
# Azure APIs Used:
#
# - az account list
# - az resource list
# - az vm list
# - az aks list
#
# Instructions:
#
# - Go to Azure Portal
# - Use Cloud Shell (Bash)
# - Upload the script
# - Run the script:
#       python3 resource-count-azure.py                 # all accessible subscriptions
#       python3 resource-count-azure.py --current       # active subscription only
#       python3 resource-count-azure.py -s <SUB_ID>     # one specific subscription
#       python3 resource-count-azure.py -s <ID> -s <ID> # several subscriptions
#       python3 resource-count-azure.py --no-refresh    # skip subscription cache refresh
#
# Notes:
# - By default the subscription cache is refreshed (az account list --refresh) so
#   newly granted subscriptions/tenants are included. Use --no-refresh to skip.
# - Active subscriptions in ANY of Enabled/Warned/PastDue states are counted;
#   only Disabled/Deleted/Expired subscriptions are skipped.
#
# Change: The 'Container Hosts (AKS Clusters)' count is now the sum of the
#         **maxCount** of all agentPoolProfiles. If maxCount is null, it uses **count**.
##########################################

import subprocess
import json
import sys
import argparse

# Azure subscription states that represent an ACTIVE subscription whose
# resources are still deployed/billable and therefore in scope for licensing.
# Only truly inactive subscriptions (Disabled/Deleted/Expired) are skipped.
ACTIVE_SUBSCRIPTION_STATES = {'Enabled', 'Warned', 'PastDue'}

# --- Comprehensive Resource Mapping for Categorization ---
RESOURCE_TO_CATEGORY = {
    # 1. Virtual Machines (VMs)
    'microsoft.compute/virtualmachines': 'Virtual Machines (VMs)',
    
    # 2. Container Hosts (AKS Clusters) - This resource type is used as a trigger for a special counting function.
    'microsoft.containerservice/managedclusters': 'Container Hosts (AKS Clusters)', 
    
    # 3. Container as a Service (CaaS)
    'microsoft.containerinstance/containergroups': 'Container as a Service (CaaS)',
    'microsoft.app/containerapps': 'Container as a Service (CaaS)',
    
    # 4. Serverless Functions
    # Functions are a kind of 'microsoft.web/sites', handled in the loop below.
    
    # 5. Cloud Buckets
    'microsoft.storage/storageaccounts': 'Cloud Buckets (Storage Accounts)',
    
    # 6. Managed Cloud Database (PaaS)
    'microsoft.sql/servers': 'Managed Cloud Database (PaaS)',
    'microsoft.sql/managedinstances': 'Managed Cloud Database (PaaS)',
    'microsoft.documentdb/databaseaccounts': 'Managed Cloud Database (PaaS)',
    'microsoft.cache/redis': 'Managed Cloud Database (PaaS)',
    'microsoft.dbformysql/servers': 'Managed Cloud Database (PaaS)',
    'microsoft.dbformysql/flexibleservers' : 'Managed Cloud Database (PaaS)',
    'microsoft.dbforpostgresql/servergroupsv2' : 'Managed Cloud Database (PaaS)',
    'microsoft.dbforpostgresql/flexibleservers' : 'Managed Cloud Database (PaaS)',
    'microsoft.dbforpostgresql/servers' : 'Managed Cloud Database (PaaS)',
    'microsoft.dbformariadb/servers' : 'Managed Cloud Database (PaaS)',

    # 7. Container Registries (ACR)
    'microsoft.containerregistry/registries': 'Container Registries (ACR)',
    
    # Web/App Services and Synapse Workspaces are intentionally EXCLUDED.
}

function_kind = 'functionapp'

# --- Global Counters ---
global_totals = {
    'Virtual Machines (VMs)': 0,
    'Container Hosts (AKS Clusters)': 0, # This will track POTENTIAL AKS Nodes
    'Container as a Service (CaaS)': 0,
    'Serverless Functions': 0,
    'Cloud Buckets (Storage Accounts)': 0,
    'Managed Cloud Database (PaaS)': 0,
    'Container Registries (ACR)': 0,
}
error_list = []

# Canonical print / summary order for all resource categories.
requested_order = [
    'Virtual Machines (VMs)',
    'Container Hosts (AKS Clusters)',
    'Container as a Service (CaaS)',
    'Serverless Functions',
    'Cloud Buckets (Storage Accounts)',
    'Managed Cloud Database (PaaS)',
    'Container Registries (ACR)'
]


def get_configured_aks_node_count(subscription_id, subscription_name):
    """
    Counts the total node potential by summing 'maxCount' (if present) or 
    falling back to 'count' for all agentPoolProfiles across all AKS clusters 
    using external 'jq'.
    """
    total_potential_nodes = 0
    
    # Command 1: Get the full AKS list JSON
    aks_list_cmd = f"az aks list --subscription {subscription_id} --output json"
    
    # Command 2: Pipe the JSON output to jq.
    # Logic: For each agentPoolProfile, use the maxCount. If maxCount is null, use the count.
    # The 'select(type == "number")' ensures we only sum numbers.
    jq_sum_cmd = """
        jq -r '
            [
                .[] | .agentPoolProfiles[]? 
                | (
                    .maxCount? // .count? 
                )
            ] 
            | map(select(type == "number"))
            | add'
    """
    
    # Execute the two commands piped together
    full_cmd = f"{aks_list_cmd} 2>/dev/null | {jq_sum_cmd}"
    
    try:
        count_output = subprocess.getoutput(full_cmd).strip()
        
        # The result from jq's add function should be a single number (as a string).
        if count_output.isdigit():
            total_potential_nodes = int(count_output)
        elif count_output == "null" or count_output == "":
            total_potential_nodes = 0
        else:
            # If we get unexpected text, record an error.
            raise ValueError(f"Unexpected output from AKS count pipe: {count_output}")

    except Exception as e:
        error_list.append(f"{subscription_name} ({subscription_id}) - Failed to execute or parse configured AKS node count. Error: {e}")
        return 0
        
    return total_potential_nodes


# --- Command-line options ---
parser = argparse.ArgumentParser(
    description="Count Azure resources for Cortex Cloud licensing/sizing."
)
parser.add_argument(
    '-s', '--subscription',
    action='append',
    metavar='SUBSCRIPTION_ID',
    help="Scope the count to a single subscription (by ID or name). Repeat the "
         "flag to include several. When omitted, ALL accessible subscriptions "
         "in the tenant are counted."
)
parser.add_argument(
    '--current',
    action='store_true',
    help="Scope the count to the currently active subscription only "
         "(i.e. the one from 'az account show')."
)
parser.add_argument(
    '--no-refresh',
    action='store_true',
    help="Skip 'az account list --refresh'. By default the local subscription "
         "cache is refreshed so newly granted subscriptions are included."
)
args = parser.parse_args()

# Fetch subscriptions. Refresh the token cache by default so subscriptions
# granted after the last 'az login' are picked up.
refresh_flag = '' if args.no_refresh else '--refresh '
az_account_list = json.loads(
    subprocess.getoutput('az account list --all {}--output json 2>&1'.format(refresh_flag))
)

# Build the set of subscription IDs/names to include, if the user scoped the run.
requested_subscriptions = set(args.subscription) if args.subscription else None
if args.current:
    try:
        current = json.loads(subprocess.getoutput('az account show --output json 2>&1'))
        requested_subscriptions = requested_subscriptions or set()
        requested_subscriptions.add(current['id'])
    except Exception as e:
        print("  [ERROR] Could not determine the current subscription: {}".format(e))
        sys.exit(1)

for az_account in az_account_list:
    # Skip subscriptions that are not active (Disabled/Deleted/Expired). Note:
    # Warned and PastDue subscriptions are still active/billable and ARE counted.
    if az_account['state'] not in ACTIVE_SUBSCRIPTION_STATES:
        continue

    # Apply subscription scoping (--subscription / --current), if requested.
    if requested_subscriptions is not None and (
        az_account['id'] not in requested_subscriptions
        and az_account['name'] not in requested_subscriptions
    ):
        continue

    subscription_name = az_account['name']
    subscription_id = az_account['id']

    print('###################################################################################')
    print("Processing Account: {} ({})".format(subscription_name, subscription_id))

    # --- Subscription-specific counters ---
    sub_census = {
        'Virtual Machines (VMs)': 0,
        'Container Hosts (AKS Clusters)': 0, # Placeholder for Potential AKS Nodes
        'Container as a Service (CaaS)': 0,
        'Serverless Functions': 0,
        'Cloud Buckets (Storage Accounts)': 0,
        'Managed Cloud Database (PaaS)': 0,
        'Container Registries (ACR)': 0,
    }

    # Flag to ensure the AKS Node count is only run once per subscription
    aks_counted_flag = False

    # ---------------------------------------------------------------
    # 1. Scan for ALL Azure VM's (Regardless of power state)
    # ---------------------------------------------------------------
    try:
        vm_command = "az vm list --subscription {} --output json 2>&1 | jq '.[].id' | wc -l".format(subscription_id)
        az_vm_list_count = subprocess.getoutput(vm_command).strip()
        sub_vm_count = int(az_vm_list_count)
        
        if sub_vm_count > 0:
            sub_census['Virtual Machines (VMs)'] = sub_vm_count
            
    except Exception as e:
        error_list.append(f"{subscription_name} ({subscription_id}) - Error executing 'az vm list'. Error: {e}")
        print(f"  [ERROR] Error executing 'az vm list'.")

    # ------------------------------------------------------------
    # 2. Scan for ALL other Azure resources and categorize them
    # ------------------------------------------------------------
    try:
        az_resource_list = subprocess.getoutput("az resource list --subscription {} --output json 2>&1".format(subscription_id))
        az_resources = json.loads(az_resource_list)
        
        for az_resource in az_resources:
            resource_type = az_resource['type'].lower()
            
            category = None
            
            # Special handling for AKS: Run the node counter when the first AKS cluster is found.
            if resource_type == 'microsoft.containerservice/managedclusters' and not aks_counted_flag:
                print("  Counting POTENTIAL (Max Capacity) AKS Nodes...")
                configured_node_count = get_configured_aks_node_count(subscription_id, subscription_name)
                sub_census['Container Hosts (AKS Clusters)'] = configured_node_count
                aks_counted_flag = True
                continue # Skip the current AKS cluster object; its count is handled by the function.
            elif resource_type == 'microsoft.containerservice/managedclusters' and aks_counted_flag:
                continue # Skip subsequent AKS cluster objects

            # Special handling for Azure Functions (Serverless Functions)
            if resource_type == 'microsoft.web/sites':
                if az_resource.get('kind') and function_kind in az_resource['kind'].lower():
                    category = 'Serverless Functions'
                else:
                    continue 
            
            # Skip resources already counted or excluded
            elif resource_type in ('microsoft.compute/virtualmachines', 'microsoft.synapse/workspaces'):
                continue 
            
            # Map all other resources
            elif resource_type in RESOURCE_TO_CATEGORY:
                category = RESOURCE_TO_CATEGORY[resource_type]
            
            if category:
                sub_census[category] = sub_census.get(category, 0) + 1
            
    except Exception as e:
        error_list.append(f"{subscription_name} ({subscription_id}) - Error executing 'az resource list'. Error: {e}")
        print(f"  [ERROR] Error executing 'az resource list'.")


    # ---------------------------------------------------------
    # 3. Print Subscription Summary and Update Globals
    # ---------------------------------------------------------
    print("\n--- Subscription Resource Census ---")

    # Print the main categories
    for category in requested_order:
        count = sub_census.get(category, 0)
        print(f"  {category}: {count}")
        global_totals[category] += count

    print('###################################################################################')

# ---------------------------------------------------------
# 4. Grand Total Summary
# ---------------------------------------------------------
print('\n###################################################################################')
print("--- GRAND TOTALS ACROSS ALL COUNTED SUBSCRIPTIONS ---")

# Print in the requested order
for category in requested_order:
    print(f"Grand Total {category}: {global_totals[category]}")

print('###################################################################################')

# ---------------------------------------------------------
# 5. Cortex Cloud Licensing Summary
#
# Maps the raw resource counts above onto the billable "Protected workloads"
# categories from the Cortex Cloud Runtime Security license plans:
#   https://cortex-docs.paloaltonetworks.com/cortex-cloud-runtime-security/get-started/understand-license-plans
#
# Billable workload types (and their billing unit) relevant to Azure infra:
#   - VMs (running or not running containers) ... 1 VM per unit
#       AKS nodes are VMs running containers and are NOT returned by 'az vm list'
#       (they live in the MC_* managed resource group), so they are added here.
#   - CaaS ..................................... 10 managed containers per unit
#   - Cloud Buckets ........................... 10 buckets per unit
#   - Managed Cloud Database (PaaS) ........... 2 PaaS databases per unit
#   - Container Images in Registries .......... 10 image scans per deployed workload
#
# Serverless Functions are NOT a billable Cortex Cloud workload type; they are
# reported above for reference only and are excluded from the licensing summary.
# ---------------------------------------------------------
billable_vms = global_totals['Virtual Machines (VMs)'] + global_totals['Container Hosts (AKS Clusters)']

print('\n###################################################################################')
print("--- CORTEX CLOUD LICENSING SUMMARY (billable workloads) ---")
print(f"VMs (billable as 'VMs', 1 unit each): {billable_vms}")
print(f"    - Standalone VMs:                 {global_totals['Virtual Machines (VMs)']}")
print(f"    - AKS nodes (VMs running containers): {global_totals['Container Hosts (AKS Clusters)']}")
print(f"CaaS Containers (10 per unit):        {global_totals['Container as a Service (CaaS)']}")
print(f"Cloud Buckets (10 per unit):          {global_totals['Cloud Buckets (Storage Accounts)']}")
print(f"Managed Cloud Databases / PaaS (2 per unit): {global_totals['Managed Cloud Database (PaaS)']}")
print(f"Container Registries -> Container Images in Registries: {global_totals['Container Registries (ACR)']}")
print("---")
print(f"Serverless Functions (NOT a billable Cortex Cloud workload; reference only): {global_totals['Serverless Functions']}")
print('###################################################################################')

print('###################################################################################')
print("Note: The 'Virtual Machines' total includes all states (Running, Stopped, Deallocated, etc.).")
print("Note: For Cortex Cloud licensing, AKS nodes count as 'VMs running containers' and are")
print("      combined with standalone VMs into the billable VM total above.")
print("Note: 'Container Hosts (AKS Clusters)' reports the total potential node count (maxCount for autoscale or count for manual).")
print("Note: 'Cloud Buckets' counts Storage Accounts (excluding Classic/ADLS Gen1).")
print("Note: 'Container Registries (ACR)' counts the total ACR found, not total container images, due to Azure API limitation.")
print("Note: DBaaS-TB-Stored, Endpoints, SaaS Users, On-Premise Data assets, and Cloud ASM are")
print("      billable Cortex Cloud categories that cannot be derived from 'az resource list' and are out of scope here.")
print()

if error_list:
    print('\n###################################################################################')
    print('Errors Encountered:')
    for this_error in error_list:
        print(this_error)
    print('###################################################################################')