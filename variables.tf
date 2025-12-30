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

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "/Users/roshpr/.ssh/sreyas_azure.pub"
}

variable "setup_script_url" {
  description = "URL of the setup script to download and execute for nginx and SSL configuration"
  type        = string
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
