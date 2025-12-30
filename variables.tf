variable "existing_resource_group_name" {
  description = "Name of the existing resource group to reuse"
  type        = string
}

variable "existing_virtual_network_name" {
  description = "Name of the existing virtual network to reuse"
  type        = string
}

variable "existing_public_subnet_name" {
  description = "Name of the existing public subnet to reuse"
  type        = string
}

variable "existing_nsg_name" {
  description = "Name of the existing network security group to reuse"
  type        = string
}

variable "vm_size" {
  description = "Azure VM size for toyshare"
  type        = string
  default     = "Standard_B4als_v2"
}

variable "root_disk_size_gb" {
  description = "Size of the root OS disk in GB"
  type        = number
  default     = 50
}

variable "data_disk_size_gb" {
  description = "Size of the data disk in GB"
  type        = number
  default     = 50
}

variable "mount_directory" {
  description = "Directory where the data disk will be mounted"
  type        = string
  default     = "/opt/toyexchange/uploads"
}

variable "domain_name" {
  description = "Domain name for the SSL certificate and nginx configuration"
  type        = string
  default     = "toy-share.org"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "/Users/roshpr/.ssh/sreyas_azure.pub"
}

variable "setup_script_url" {
  description = "URL of the setup script to download and execute for nginx and SSL configuration"
  type        = string
}

variable "restricted_ssh_ips" {
  description = "IP ranges allowed to access SSH (port 22)"
  type        = list(string)
  default     = ["170.85.154.0/24"]
}

variable "restricted_app_ips" {
  description = "IP ranges allowed to access Node.js directly (port 3000)"
  type        = list(string)
  default     = ["170.85.154.0/24", "172.126.69.0/24"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "ToyShare"
    Owner       = "DevOps Team"
  }
}
