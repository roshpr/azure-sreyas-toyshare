# Existing infrastructure references
existing_resource_group_name   = "rg-sreyas-projects"
existing_virtual_network_name  = "vnet-sreyas-projects"
existing_public_subnet_name    = "subnet-sreyas-projects-public"
existing_nsg_name              = "nsg-sreyas-projects-public"

# SSH configuration
ssh_public_key_path = "/Users/roshpr/.ssh/sreyas_azure.pub"

# VM configuration
vm_size           = "Standard_B2ms"
root_disk_size_gb = 50
data_disk_size_gb = 50
mount_directory   = "/opt/toyexchange/uploads"
domain_name       = "toy-share.org"

# Security configuration
restricted_ssh_ips = ["170.85.154.0/24"]
restricted_app_ips = ["170.85.154.0/24", "172.126.69.0/24"]

# Setup script URL - You need to host this script somewhere accessible
# Examples:
# - GitHub Gist raw URL
# - Azure Blob Storage with public access
# - Any public web server
setup_script_url = "https://raw.githubusercontent.com/roshpr/azure-sreyas-toyshare/refs/heads/main/setup-toyshare-nginx.sh"

# Tags
tags = {
  Environment = "Development"
  Project     = "ToyShare"
  Owner       = "DevOps Team"
  Purpose     = "Node.js file sharing application"
}
