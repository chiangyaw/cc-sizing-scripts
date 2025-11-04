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
#       python3 resource-count-azure.py
#
# Change: The 'Container Hosts (AKS Clusters)' count is now the sum of the 
#         **maxCount** of all agentPoolProfiles. If maxCount is null, it uses **count**.
##########################################

import subprocess
import json
import sys

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


# Fetch all subscriptions
az_account_list = json.loads(subprocess.getoutput('az account list --all --output json 2>&1'))

for az_account in az_account_list:
    if az_account['state'] != 'Enabled':
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
    
    requested_order = [
        'Virtual Machines (VMs)', 
        'Container Hosts (AKS Clusters)', 
        'Container as a Service (CaaS)', 
        'Serverless Functions', 
        'Cloud Buckets (Storage Accounts)', 
        'Managed Cloud Database (PaaS)', 
        'Container Registries (ACR)'
    ]
    
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
print("--- GRAND TOTALS ACROSS ALL ENABLED SUBSCRIPTIONS ---")

# Print in the requested order
for category in requested_order:
    print(f"Grand Total {category}: {global_totals[category]}")

print('###################################################################################')
print("Note: The 'Virtual Machines' total includes all states (Running, Stopped, Deallocated, etc.).")
print("Note: 'Container Hosts (AKS Clusters)' reports the total potential node count (maxCount for autoscale or count for manual).")
print("Note: 'Cloud Buckets' counts Storage Accounts (excluding Classic/ADLS Gen1).")
print("Note: 'Container Registries (ACR)' counts the total ACR found, not total container image due to Azure API limitation.")
print()

if error_list:
    print('\n###################################################################################')
    print('Errors Encountered:')
    for this_error in error_list:
        print(this_error)
    print('###################################################################################')