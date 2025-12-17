# Azure Cross-Region VM Migrator

A Bash script to automate the migration of Azure Virtual Machines from one region to another.
This tool handles the snapshotting, copying, and recreation of VMs while addressing common deployment failures related to Availability Zones and Network Security Groups.

## 🚀 Key Features (v2.0)

* **Cross-Region Migration:** Moves VMs (including L-Series/NVMe supported sizes) between any Azure regions.
* **Availability Zone Safe:** Automatically handles VM creation without forcing source Availability Zones, preventing `ZonalAllocationFailed` errors in target regions.
* **Connectivity Ready:** Automatically opens **Port 22 (SSH)** in the new Network Security Group (NSG) to prevent lockout.
* **Zero Data Loss:** Uses incremental snapshots to copy OS disks securely.
* **Non-Destructive:** The source VM is **not deleted**, ensuring a safe fallback.

## 📋 Prerequisites

1.  **Azure CLI:** Make sure you have `az` installed and logged in (`az login`).
2.  **Target Network:** You must have a VNet and Subnet created in the target region before running the script.
3.  **Permissions:** Contributor access to both source and target Resource Groups.

## 🛠️ Usage

Make the script executable:
```bash
chmod +x vm-move.sh
```
״״
Run the script with the following arguments:

```bash
./vm-move.sh <SOURCE_VM_ID> <TARGET_REGION> <TARGET_RG> <TARGET_VNET> <TARGET_SUBNET>
```

Example:

```bash
./vm-move.sh \
  "/subscriptions/xxxxx/resourceGroups/SourceRG/providers/Microsoft.Compute/virtualMachines/MyVM" \
  "eastus2" \
  "TargetRG" \
  "vnet-target" \
  "default"
  ```




⚠️ Important Limitations & Warnings
1. Network Security Groups (NSG)
The script creates a basic NSG and automatically opens SSH (Port 22).

CRITICAL: Complex firewall rules (Allow/Deny specific IPs, ASGs) from the source are NOT copied automatically. You must verify and recreate specific security rules manually after migration.

2. Private IPs
The new VM will receive a new Private IP address assigned by the target subnet. Static Private IPs are not preserved.

3. Source VM
The source VM is deallocated (stopped) but NOT deleted.

Recommendation: Keep the source VM for at least 7 days as a backup before manual deletion.

📝 License
This script is provided "as is" without warranty of any kind. Use at your own risk.




