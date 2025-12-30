terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "azurerm" {
  features {}
}

# Data source to reference existing resource group
data "azurerm_resource_group" "existing" {
  name = var.existing_resource_group_name
}

# Data source to reference existing virtual network
data "azurerm_virtual_network" "existing" {
  name                = var.existing_virtual_network_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

# Data source to reference existing public subnet
data "azurerm_subnet" "public" {
  name                 = var.existing_public_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = data.azurerm_resource_group.existing.name
}

# Data source to reference existing network security group
data "azurerm_network_security_group" "public" {
  name                = var.existing_nsg_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

# Public IP for toyshare VM
resource "azurerm_public_ip" "toyshare_vm_pip" {
  name                = "pip-toyshare-vm"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "toyshare-vm"
  tags                = var.tags
}

# Network Interface for toyshare VM
resource "azurerm_network_interface" "toyshare_vm_nic" {
  name                = "nic-toyshare-vm"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg-toyshare"
    subnet_id                     = data.azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.toyshare_vm_pip.id
  }
}

# Associate NIC with existing NSG
resource "azurerm_network_interface_security_group_association" "toyshare_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.toyshare_vm_nic.id
  network_security_group_id = data.azurerm_network_security_group.public.id
}

# Data disk for toyshare
resource "azurerm_managed_disk" "toyshare_data" {
  name                = "disk-toyshare-data"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  storage_account_type = "Standard_LRS"
  create_option       = "Empty"
  disk_size_gb        = 50
  tags                = var.tags
}

# Cloud-init script for VM setup
locals {
  cloud_init_config = <<-EOT
#!/bin/bash
# Log all output to /tmp/toyshare_setup.log
exec > >(tee -a /tmp/toyshare_setup.log) 2>&1

echo "Starting toyshare VM setup..."

# Update system
apt-get update
apt-get install -y curl wget git nginx openssl

# Create mount point and mount data disk
mkdir -p /www/data

# Wait for data disk to be available
echo "Waiting for data disk..."
while [ ! -b /dev/disk/azure/scsi1/lun0 ]; do
  sleep 2
done

# Format and mount data disk
echo "Formatting and mounting data disk..."
mkfs -t ext4 /dev/disk/azure/scsi1/lun0

# Add to fstab for automatic mounting on boot
echo "Adding fstab entry..."
UUID=$(blkid -s UUID -o value /dev/disk/azure/scsi1/lun0)
echo "UUID=$UUID   /www/data   ext4   defaults,nofail   1   2" >> /etc/fstab

# Mount the disk
mount -a

# Verify mount
df -h /www/data

# Download and execute setup script
echo "Downloading setup script from: ${var.setup_script_url}"
cd /tmp
wget -O setup.sh "${var.setup_script_url}"
chmod +x setup.sh
./setup.sh

echo "Toyshare VM setup completed successfully!"
EOT
}

# toyshare VM
resource "azurerm_linux_virtual_machine" "toyshare_vm" {
  name                = "toysharevm"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  size                = "Standard_D4s_v3"  # 4 vCPUs
  admin_username      = "azureuser"
  disable_password_authentication = true
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.toyshare_vm_nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "24_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(local.cloud_init_config)

  # Attach data disk
  additional_capabilities {
    ultra_ssd_enabled = false
  }
}

# Attach data disk to VM
resource "azurerm_virtual_machine_data_disk_attachment" "toyshare_data_attach" {
  managed_disk_id           = azurerm_managed_disk.toyshare_data.id
  virtual_machine_id        = azurerm_linux_virtual_machine.toyshare_vm.id
  lun                       = 0
  caching                   = "ReadWrite"
  write_accelerator_enabled = false
}

# Outputs
output "toyshare_vm_public_ip" {
  value = azurerm_public_ip.toyshare_vm_pip.ip_address
}

output "toyshare_vm_private_ip" {
  value = azurerm_network_interface.toyshare_vm_nic.private_ip_address
}

output "toyshare_vm_fqdn" {
  value = azurerm_public_ip.toyshare_vm_pip.fqdn
}

output "toyshare_data_disk_id" {
  value = azurerm_managed_disk.toyshare_data.id
}
