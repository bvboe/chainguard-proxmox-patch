#!/bin/bash
#
# create-chainguard-qemu-vm.sh
#
# Creates a Chainguard QEMU VM on Proxmox VE from a qcow2 image
# Tested on Proxmox VE 9.1.1
#

set -e

# Configuration
VMID="${1:-110}"
VM_NAME="${2:-chainguard-vm}"
QCOW2_IMAGE="/mnt/pve/Wall-E-NFS/import/qemu-docker-full-amd64-20251121-0325.qcow2"
MEMORY=2048
CORES=2
STORAGE="local-lvm"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating Chainguard QEMU VM${NC}"
echo "  VM ID: $VMID"
echo "  VM Name: $VM_NAME"
echo "  Source Image: $QCOW2_IMAGE"
echo "  Memory: ${MEMORY}MB"
echo "  Cores: $CORES"
echo "  Storage: $STORAGE"
echo ""

# Check if VM already exists
if qm status "$VMID" &>/dev/null; then
    echo -e "${RED}Error: VM $VMID already exists${NC}"
    exit 1
fi

# Check if source image exists
if [ ! -f "$QCOW2_IMAGE" ]; then
    echo -e "${RED}Error: Source image not found: $QCOW2_IMAGE${NC}"
    exit 1
fi

echo -e "${GREEN}Step 1: Creating VM${NC}"
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf \
  --machine q35 \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --cpu x86-64-v2-AES

echo -e "${GREEN}Step 2: Importing disk from qcow2 image${NC}"
qm importdisk "$VMID" "$QCOW2_IMAGE" "$STORAGE"

echo -e "${GREEN}Step 3: Attaching disk as bootable SCSI device with iothread${NC}"
qm set "$VMID" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,iothread=1" --boot order=scsi0

echo -e "${GREEN}Step 4: Creating EFI disk (UEFI boot)${NC}"
qm set "$VMID" --efidisk0 "${STORAGE}:1,format=raw,efitype=4m"

echo ""
echo -e "${GREEN}VM $VMID created successfully!${NC}"
echo ""
echo "Configuration:"
qm config "$VMID"
echo ""
echo "To start the VM, run:"
echo "  qm start $VMID"
echo ""
echo "To access the console, run:"
echo "  qm terminal $VMID"
