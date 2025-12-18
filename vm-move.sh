#!/bin/bash
set -e

# --- Configuration & Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Helper Functions ---
log_header() {
    echo -e "\n${CYAN}>>> [$(date +"%H:%M:%S")] $1...${NC}"
    STEP_START=$SECONDS
}

log_success() {
    DURATION=$(( SECONDS - STEP_START ))
    echo -e "${GREEN}[ DONE ] (Total Step Duration: ${DURATION}s)${NC}"
}

# --- Arguments Check ---
if [ "$#" -ne 5 ]; then
    echo -e "${RED}Usage: $0 <source_vm_id> <target_region> <target_rg> <target_vnet_name> <target_subnet_name>${NC}"
    exit 1
fi

SOURCE_VM_ID=$1
TARGET_REGION=$2
TARGET_RG=$3
TARGET_VNET_NAME=$4
TARGET_SUBNET_NAME=$5

clear
echo -e "${CYAN}========================================================"
echo -e "   AZURE VM CROSS-REGION MIGRATION TOOL v2.6"
echo -e "   Status: Production Ready / UX Optimized"
echo -e "========================================================${NC}"

# 1. Metadata
log_header "Step 1: Retrieving Source Metadata"
VM_NAME=$(az vm show --ids "$SOURCE_VM_ID" --query name -o tsv --only-show-errors)
OS_DISK_ID=$(az vm show --ids "$SOURCE_VM_ID" --query storageProfile.osDisk.managedDisk.id -o tsv --only-show-errors)
VM_SIZE=$(az vm show --ids "$SOURCE_VM_ID" --query hardwareProfile.vmSize -o tsv --only-show-errors)
SOURCE_LOCATION=$(az vm show --ids "$SOURCE_VM_ID" --query location -o tsv --only-show-errors)
SOURCE_RG=$(echo "$SOURCE_VM_ID" | cut -d'/' -f5)
echo "   VM: $VM_NAME | Size: $VM_SIZE"
log_success

# 2. Deallocate
log_header "Step 2: Stopping Source VM"
az vm deallocate --ids "$SOURCE_VM_ID" --only-show-errors
log_success

# 3. Create Snapshot
log_header "Step 3: Creating Incremental Snapshot (Source)"
SNAPSHOT_NAME="${VM_NAME}-snap-$(date +%s)"
SNAPSHOT_ID=$(az snapshot create \
    --resource-group "$SOURCE_RG" \
    --name "$SNAPSHOT_NAME" \
    --source "$OS_DISK_ID" \
    --location "$SOURCE_LOCATION" \
    --incremental true \
    --sku Standard_LRS \
    --query id -o tsv --only-show-errors)
log_success

# 4. Copy Snapshot with 30s Heartbeat
log_header "Step 4: Copying Snapshot to $TARGET_REGION"
TARGET_SNAPSHOT_NAME="${SNAPSHOT_NAME}-target"

az snapshot create \
    --resource-group "$TARGET_RG" \
    --name "$TARGET_SNAPSHOT_NAME" \
    --location "$TARGET_REGION" \
    --source "$SNAPSHOT_ID" \
    --incremental true \
    --copy-start --only-show-errors -o none

echo -e "   Transfer started. Polling status every 5s. Heartbeat every 30s."
echo -n "   Progress: "

PREV_PERCENT="-1"
SECONDS_SINCE_UPDATE=0
POLL_INTERVAL=5

while true; do
    PERCENT=$(az snapshot show --name "$TARGET_SNAPSHOT_NAME" --resource-group "$TARGET_RG" --query completionPercent -o tsv --only-show-errors 2>/dev/null || echo "0.0")
    
    if [ "$PERCENT" != "$PREV_PERCENT" ]; then
        echo -ne "${YELLOW}${PERCENT}%${NC}..."
        PREV_PERCENT=$PERCENT
        SECONDS_SINCE_UPDATE=0 # Reset heartbeat counter
    else
        SECONDS_SINCE_UPDATE=$((SECONDS_SINCE_UPDATE + POLL_INTERVAL))
    fi

    # Heartbeat logic: if no change for 30 seconds, print a status dot/message
    if [ $SECONDS_SINCE_UPDATE -ge 30 ]; then
        echo -ne "${CYAN}(still working: ${PERCENT}%)${NC}..."
        SECONDS_SINCE_UPDATE=0
    fi

    if [ "$PERCENT" == "100.0" ]; then
        echo -e "\n   ${GREEN}Snapshot data fully synchronized.${NC}"
        break
    fi
    sleep $POLL_INTERVAL
done
log_success

# 5. Create Disk
log_header "Step 5: Creating Managed Disk"
TARGET_DISK_NAME="${VM_NAME}-osdisk-new"
az disk create --resource-group "$TARGET_RG" --name "$TARGET_DISK_NAME" --location "$TARGET_REGION" --source "$TARGET_SNAPSHOT_NAME" --sku Premium_LRS --only-show-errors -o none
TARGET_DISK_ID=$(az disk show --resource-group "$TARGET_RG" --name "$TARGET_DISK_NAME" --query id -o tsv --only-show-errors)
log_success

# 6. Networking
log_header "Step 6: Network & Security Provisioning"
az network public-ip create --resource-group "$TARGET_RG" --name "${VM_NAME}-pip" --location "$TARGET_REGION" --sku Standard --allocation-method Static --only-show-errors -o none
az network nsg create --resource-group "$TARGET_RG" --name "${VM_NAME}-nsg" --location "$TARGET_REGION" --only-show-errors -o none
az network nsg rule create --resource-group "$TARGET_RG" --nsg-name "${VM_NAME}-nsg" --name Allow-SSH-Auto --protocol Tcp --priority 1000 --destination-port-range 22 --access Allow --only-show-errors -o none
az network nic create --resource-group "$TARGET_RG" --name "${VM_NAME}-nic" --location "$TARGET_REGION" --subnet "$TARGET_SUBNET_NAME" --vnet-name "$TARGET_VNET_NAME" --network-security-group "${VM_NAME}-nsg" --public-ip-address "${VM_NAME}-pip" --only-show-errors -o none
NIC_ID=$(az network nic show --resource-group "$TARGET_RG" --name "${VM_NAME}-nic" --query id -o tsv --only-show-errors)
log_success

# 7. Create VM
log_header "Step 7: Recreating Virtual Machine"
az vm create --resource-group "$TARGET_RG" --name "$VM_NAME" --location "$TARGET_REGION" --size "$VM_SIZE" --os-type Linux --attach-os-disk "$TARGET_DISK_ID" --nics "$NIC_ID" --only-show-errors -o none
log_success

# Summary
NEW_IP=$(az network public-ip show --resource-group "$TARGET_RG" --name "${VM_NAME}-pip" --query ipAddress -o tsv --only-show-errors)
echo -e "\n${GREEN}========================================================"
echo -e "   SUCCESS! New IP: $NEW_IP"
echo -e "   Total Time: $SECONDS seconds"
echo -e "========================================================${NC}"
