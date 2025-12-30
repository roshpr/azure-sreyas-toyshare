# Azure ToyShare Terraform Project

This Terraform project creates a toyshare VM with Node.js application, nginx with SSL, and data disk storage.

## Architecture

- **VM**: Standard_D4s_v3 (4 vCPUs, 16GB RAM)
- **OS**: Ubuntu 24.04 LTS
- **Root Disk**: 50GB Standard_LRS
- **Data Disk**: 50GB Standard_LRS mounted at `/www/data`
- **Web Server**: Nginx with HTTPS (port 443)
- **SSL**: Self-signed certificate for `toy-share.org`
- **Application**: Node.js with PM2 process manager
- **Data Storage**: `/www/data` with automatic mount on boot

## Prerequisites

1. Azure CLI installed and configured
2. Terraform >= 1.0
3. Existing Azure infrastructure (resource group, VNet, subnets, NSG)
4. SSH key at `/Users/roshpr/.ssh/sreyas_azure.pub`

## Setup Instructions

### 1. Host the Setup Script

The setup script needs to be publicly accessible. Upload `setup-toyshare-nginx.sh` to one of:

- GitHub Gist (get raw URL)
- Azure Blob Storage with public access
- Any public web server

Update `terraform.tfvars` with the script URL.

### 2. Configure Terraform Variables

Copy and edit `terraform.tfvars`:

```hcl
# Update these values based on your existing infrastructure
existing_resource_group_name   = "your-resource-group-name"
existing_virtual_network_name  = "your-vnet-name"
existing_public_subnet_name    = "your-public-subnet-name"
existing_nsg_name              = "your-nsg-name"

# Update with your script URL
setup_script_url = "https://your-domain.com/setup-toyshare-nginx.sh"
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

## Post-Deployment

### Access the Application

After deployment, you can access:

- **HTTP**: Redirects to HTTPS
- **HTTPS**: `https://<vm-public-ip>/` (self-signed certificate warning)
- **Health Check**: `/health`
- **API Status**: `/api/status`
- **File Browser**: `/data`

### SSH Access

```bash
ssh -i /Users/roshpr/.ssh/sreyas_azure azureuser@<vm-public-ip>
```

### File Management

Files are stored in `/www/data` on the VM. You can:

- Upload files via SCP/SFTP
- Use the web interface at `/data`
- Access via API at `/api/files`

## Monitoring

### Application Logs

```bash
# PM2 logs
pm2 logs toyshare

# Nginx logs
tail -f /var/log/nginx/toy-share.org_access.log
tail -f /var/log/nginx/toy-share.org_error.log
```

### System Status

```bash
# Check PM2 status
pm2 status

# Check nginx status
systemctl status nginx

# Check disk usage
df -h /www/data
```

## Security Considerations

- Self-signed SSL certificate will show browser warnings
- SSH access restricted to configured IPs in NSG
- Rate limiting configured in nginx
- File upload restrictions in place

## Customization

### Domain Configuration

To use a custom domain instead of the IP address:

1. Update the `DOMAIN` variable in `setup-toyshare-nginx.sh`
2. Point your domain's A record to the VM's public IP
3. Consider replacing the self-signed certificate with Let's Encrypt

### Application Code

Replace the placeholder Node.js application in `/opt/toyshare/app.js` with your actual application code.

### SSL Certificate

For production, replace the self-signed certificate with a proper SSL certificate from a certificate authority.

## Troubleshooting

### Common Issues

1. **Setup script fails to download**: Check the URL is publicly accessible
2. **Data disk not mounting**: Check `/tmp/toyshare_setup.log` on the VM
3. **Nginx fails to start**: Check SSL certificate paths and nginx configuration
4. **Application not accessible**: Check PM2 status and port configuration

### Log Locations

- Cloud-init log: `/tmp/toyshare_setup.log`
- Nginx logs: `/var/log/nginx/`
- Application logs: PM2 logs (`pm2 logs toyshare`)

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: This will not affect the shared resource group, VNet, or other infrastructure.
