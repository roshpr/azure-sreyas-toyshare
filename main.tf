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

# Network Security Group for toyshare VM
resource "azurerm_network_security_group" "toyshare_nsg" {
  name                = "nsg-toyshare-vm"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  tags                = var.tags

  security_rule {
    name                       = "SSH-Restricted"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.restricted_ssh_ips
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP-Public"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS-Public"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "NodeJS-Restricted"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefixes    = var.restricted_app_ips
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate toyshare NIC with its own NSG
resource "azurerm_network_interface_security_group_association" "toyshare_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.toyshare_vm_nic.id
  network_security_group_id = azurerm_network_security_group.toyshare_nsg.id
}

# Data disk for toyshare
resource "azurerm_managed_disk" "toyshare_data" {
  name                = "disk-toyshare-data"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  storage_account_type = "Standard_LRS"
  create_option       = "Empty"
  disk_size_gb        = var.data_disk_size_gb
  tags                = var.tags
}

# Cloud-init script for VM setup
locals {
  cloud_init_config = <<-EOT
#!/bin/bash
# Log all output to /tmp/toyshare_setup.log
exec > >(tee -a /tmp/toyshare_setup.log) 2>&1

echo "Starting ToyShare VM setup..."

# Wait for the data disk to be available
echo "Waiting for data disk to be available..."
while [ ! -b /dev/disk/azure/scsi1/lun0 ]; do
  echo "Waiting for data disk..."
  sleep 5
done

# Check if the disk already has a filesystem
echo "Checking disk filesystem..."
if ! blkid /dev/disk/azure/scsi1/lun0; then
    echo "Creating filesystem on data disk..."
    mkfs -t ext4 /dev/disk/azure/scsi1/lun0
else
    echo "Filesystem already exists on data disk"
fi

# Create mount point and mount the data disk directly to uploads directory
echo "Mounting data disk to ${var.mount_directory}..."
mkdir -p ${var.mount_directory}
mount /dev/disk/azure/scsi1/lun0 ${var.mount_directory}

# Add to fstab for automatic mounting
echo "Adding to fstab..."
UUID=$$(blkid -s UUID -o value /dev/disk/azure/scsi1/lun0)
echo "UUID=$$UUID  ${var.mount_directory}  ext4  defaults,nofail  0  2" >> /etc/fstab

# Create logs directory
echo "Setting up directory structure..."
mkdir -p /opt/toyexchange/logs

# Set proper permissions for uploads directory (writable by nodejs app)
chown -R www-data:www-data /opt/toyexchange
chmod -R 755 /opt/toyexchange
chmod 775 ${var.mount_directory}

# Create logrotate configuration for toyexchange logs
echo "Setting up logrotate configuration..."
cat > /etc/logrotate.d/toyexchange << 'EOF'
/opt/toyexchange/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        pm2 reloadLogs
    endscript
}
EOF

# Ensure logrotate is installed and configured
apt-get update
apt-get install -y logrotate

# Test logrotate configuration
echo "Testing logrotate configuration..."
logrotate -d /etc/logrotate.d/toyexchange

# Create environment file for toyexchange app
echo "Creating environment file..."
cat > /opt/toyexchange/.env << ENVEOF
NODE_ENV=production
PORT=3000
UPLOADS_DIR=${var.mount_directory}
ENVEOF

# Download and execute the setup script for nginx and SSL
echo "Downloading and executing setup script..."
curl -fsSL "${var.setup_script_url}" | bash -s -- "${var.domain_name}" "${var.mount_directory}"

echo "ToyShare VM setup completed successfully!"
EOT
}

# toyshare VM
resource "azurerm_linux_virtual_machine" "toyshare_vm" {
  name                = "toysharevm"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  size                = var.vm_size
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
    disk_size_gb         = var.root_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
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
