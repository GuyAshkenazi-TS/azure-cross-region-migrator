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
