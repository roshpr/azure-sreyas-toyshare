# Existing infrastructure references
existing_resource_group_name   = "rg-sreyas-projects"
existing_virtual_network_name  = "vnet-sreyas-projects"
existing_public_subnet_name    = "subnet-sreyas-projects-public"
existing_nsg_name              = "nsg-sreyas-projects-public"

# SSH configuration
ssh_public_key_path = "/Users/roshpr/.ssh/sreyas_azure.pub"

# Setup script URL - You need to host this script somewhere accessible
# Examples:
# - GitHub Gist raw URL
# - Azure Blob Storage with public access
# - Any public web server
setup_script_url = "https://gist.githubusercontent.com/roshpr/7f50f7f00e1d4e9785bb8f9788e6f08e/raw/cac23a69bd5ab2fc6711fcc9fc52786819d999fd/sreyas_toyshare_gist.sh"

# Tags
tags = {
  Environment = "Development"
  Project     = "ToyShare"
  Owner       = "DevOps Team"
  Purpose     = "Node.js file sharing application"
}
