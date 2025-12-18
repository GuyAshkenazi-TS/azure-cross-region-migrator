# Azure VM Cross-Region Migrator (v2.6)

A professional Bash script designed to automate the migration of Azure Virtual Machines between different regions. This tool is specifically engineered to handle complex scenarios such as **L-Series/NVMe-based VMs**, **Trusted Launch** security configurations, and cross-region synchronization delays.



## ✨ Key Features (v2.6)

* **Real-Time Progress Monitoring:** Features a visual progress bar during snapshot transfers to keep the user informed.
* **30-Second Heartbeat:** Provides periodic "still working" status updates even when the transfer percentage remains unchanged, ensuring the session remains active and transparent.
* **Detailed Timestamps:** Logs the exact start time for every step in the migration process.
* **Automatic Duration Tracking:** Calculates and displays the total execution time for each individual step and the overall process.
* **Trusted Launch Support:** Utilizes incremental snapshots required for modern Azure security standards.
* **Auto-SSH Readiness:** Automatically provisions a Network Security Group (NSG) and opens Port 22 (SSH) to ensure immediate connectivity after migration.
* **Capacity-Aware Deployment:** Recreates the VM without forcing specific Availability Zones to avoid capacity restriction errors in the target region.

## 📋 Prerequisites

**CRITICAL:** The script assumes that the target network infrastructure is already in place. Before running the script, ensure the following resources exist in your target region:

1. **Target Resource Group:** A container for your new resources.
2. **Target VNet & Subnet:** A virtual network and at least one active subnet (e.g., named `default`).

### Example: Preparing the Target Environment (Azure CLI)
```bash
# 1. Create the Target Resource Group
az group create --name Lab-Target-RG --location eastus2

# 2. Create the Target VNet and Subnet
az network vnet create \
  --resource-group Lab-Target-RG \
  --name Vnet-Target \
  --location eastus2 \
  --address-prefix 10.5.0.0/16 \
  --subnet-name default \
  --subnet-prefix 10.5.1.0/24
```

  🛠️ How to Use
1. Grant Execution Permissions:
```bash
chmod +x vm-move.sh
```
2. Run the Script:

```bash 
./vm-move.sh <SOURCE_VM_ID> <TARGET_REGION> <TARGET_RG> <TARGET_VNET_NAME> <TARGET_SUBNET_NAME>
```


Execution Example:
```bash 
./vm-move.sh \
  "/subscriptions/xxxx-xxxx-xxxx/resourceGroups/SourceRG/providers/Microsoft.Compute/virtualMachines/MyVM" \
  "eastus2" \
  "Lab-Target-RG" \
  "Vnet-Target" \
  "default"
  ```

## ⚠️ Important Warnings & Limitations
Network Security Groups (NSG): The script creates a basic NSG and opens Port 22 only. Complex rules, such as specific IP whitelists or Application Security Groups (ASGs), are NOT copied and must be recreated manually.

Source VM Downtime: The source VM will be Deallocated (stopped) during the process to ensure 100% data consistency.

Private IP Changes: The VM will receive a new internal IP address from the target subnet's range.

Snapshot Retention: Source snapshots are not deleted automatically; they should be kept as a backup for a "cooling period" before manual deletion.

## 📝 License
This script is provided "as is" without warranty of any kind. It is highly recommended to perform a test run in a development/lab environment before migrating production workloads.
