#!/bin/bash

# Check arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <source_vm_id> <target_region> <target_rg> <target_vnet_name> <target_subnet_name>"
    echo "Example: $0 /subscriptions/.../providers/Microsoft.Compute/virtualMachines/MyVM eastus2 MyTargetRG MyVnet default"
    exit 1
fi

SOURCE_VM_ID=$1
TARGET_REGION=$2
TARGET_RG=$3
TARGET_VNET_NAME=$4
TARGET_SUBNET_NAME=$5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Starting VM Migration Script v2.0 ===${NC}"
echo "Source VM ID: $SOURCE_VM_ID"
echo "Target Region: $TARGET_REGION"

# 1. Get Source Details
echo -e "\n${YELLOW}Step 1: Retrieving Source Metadata...${NC}"
VM_NAME=$(az vm show --ids $SOURCE_VM_ID --query name -o tsv)
OS_DISK_ID=$(az vm show --ids $SOURCE_VM_ID --query storageProfile.osDisk.managedDisk.id -o tsv)
OS_TYPE=$(az vm show --ids $SOURCE_VM_ID --query storageProfile.osDisk.osType -o tsv)
VM_SIZE=$(az vm show --ids $SOURCE_VM_ID --query hardwareProfile.vmSize -o tsv)

echo "Detected VM Name: $VM_NAME"
echo "Detected OS Type: $OS_TYPE"
echo "Detected Size: $VM_SIZE"

# 2. Create Target Resource Group
echo -e "\n${YELLOW}Step 2: Ensuring Target Resource Group exists...${NC}"
az group create --name $TARGET_RG --location $TARGET_REGION -o none

# 3. Snapshot Source OS Disk
echo -e "\n${YELLOW}Step 3: Creating Snapshot of Source Disk...${NC}"
SNAPSHOT_NAME="${VM_NAME}-snap-$(date +%s)"
az snapshot create --resource-group $(echo $SOURCE_VM_ID | cut -d'/' -f5) --name $SNAPSHOT_NAME --source $OS_DISK_ID --location $(az vm show --ids $SOURCE_VM_ID --query location -o tsv) --sku Standard_LRS -o none

# 4. Copy Snapshot to Target Region (This takes time)
echo -e "\n${YELLOW}Step 4: Copying Snapshot to Target Region ($TARGET_REGION)...${NC}"
TARGET_SNAPSHOT_NAME="${SNAPSHOT_NAME}-target"
az snapshot create --resource-group $TARGET_RG --name $TARGET_SNAPSHOT_NAME --source "/subscriptions/$(echo $SOURCE_VM_ID | cut -d'/' -f3)/resourceGroups/$(echo $SOURCE_VM_ID | cut -d'/' -f5)/providers/Microsoft.Compute/snapshots/$SNAPSHOT_NAME" --location $TARGET_REGION --sku Standard_LRS -o none

# 5. Create Managed Disk from Snapshot
echo -e "\n${YELLOW}Step 5: Creating Managed Disk in Target Region...${NC}"
TARGET_DISK_NAME="${VM_NAME}-osdisk-new"
az disk create --resource-group $TARGET_RG --name $TARGET_DISK_NAME --location $TARGET_REGION --source $TARGET_SNAPSHOT_NAME --sku Premium_LRS -o none
TARGET_DISK_ID=$(az disk show --resource-group $TARGET_RG --name $TARGET_DISK_NAME --query id -o tsv)

# 6. Create Networking (IP, NSG, NIC)
echo -e "\n${YELLOW}Step 6: Creating Network Resources...${NC}"

# Public IP
az network public-ip create --resource-group $TARGET_RG --name "${VM_NAME}-pip" --location $TARGET_REGION --sku Standard --allocation-method Static -o none

# NSG - Creating basic NSG
echo "Creating NSG..."
az network nsg create --resource-group $TARGET_RG --name "${VM_NAME}-nsg" --location $TARGET_REGION -o none

# --- FIX: Auto Open SSH ---
echo -e "${GREEN}Action: Automatically opening SSH (Port 22) on the new NSG...${NC}"
az network nsg rule create \
    --resource-group $TARGET_RG \
    --nsg-name "${VM_NAME}-nsg" \
    --name Allow-SSH-Auto \
    --protocol Tcp \
    --priority 1000 \
    --destination-port-range 22 \
    --access Allow \
    -o none

# Create NIC
az network nic create \
    --resource-group $TARGET_RG \
    --name "${VM_NAME}-nic" \
    --location $TARGET_REGION \
    --subnet $TARGET_SUBNET_NAME \
    --vnet-name $TARGET_VNET_NAME \
    --network-security-group "${VM_NAME}-nsg" \
    --public-ip-address "${VM_NAME}-pip" \
    -o none

NIC_ID=$(az network nic show --resource-group $TARGET_RG --name "${VM_NAME}-nic" --query id -o tsv)

# 7. Create VM
echo -e "\n${YELLOW}Step 7: Creating the Virtual Machine...${NC}"
echo "NOTE: Creating VM without forcing Availability Zones to ensure success."

# --- FIX: Removed --zone parameter ---
az vm create \
    --resource-group $TARGET_RG \
    --name $VM_NAME \
    --location $TARGET_REGION \
    --size $VM_SIZE \
    --os-type $OS_TYPE \
    --attach-os-disk $TARGET_DISK_ID \
    --nics $NIC_ID \
    -o none

# 8. Summary and Warnings
NEW_IP=$(az network public-ip show --resource-group $TARGET_RG --name "${VM_NAME}-pip" --query ipAddress -o tsv)

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   MIGRATION COMPLETED SUCCESSFULLY!   ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "New VM IP Address: ${YELLOW}$NEW_IP${NC}"
echo -e "SSH Connection: ssh <user>@$NEW_IP"
echo ""
echo -e "${RED}⚠️  IMPORTANT WARNING REGARDING SECURITY GROUPS (NSG):${NC}"
echo "This script created a basic NSG and opened Port 22 (SSH) for you."
echo "However, your original NSG rules (complex rules, restricted IPs) were NOT copied."
echo "YOU MUST manually verify and recreate specific firewall rules if needed."
echo "Guide: https://learn.microsoft.com/en-us/azure/virtual-network/manage-network-security-group"
echo ""
echo -e "${YELLOW}Recommendation regarding Source VM:${NC}"
echo "The source VM was NOT deleted. Keep it as a backup for at least 7 days."
echo "=============================================="
