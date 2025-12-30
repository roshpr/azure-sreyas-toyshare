#!/bin/bash
# Setup script for ToyShare nginx and SSL configuration
# This script sets up nginx with self-signed SSL certificate for toy-share.org

set -e

echo "Starting ToyShare nginx and SSL setup..."

# Configuration variables
DOMAIN="${1:-toy-share.org}"
MOUNT_DIR="${2:-/opt/toyexchange/uploads}"
SSL_DIR="/etc/ssl/certs"
SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

# Create SSL directory
echo "Creating SSL directory..."
mkdir -p "${SSL_DIR}"

# Generate self-signed SSL certificate
echo "Generating self-signed SSL certificate for ${DOMAIN}..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${SSL_DIR}/privkey.pem" \
    -out "${SSL_DIR}/fullchain.pem" \
    -subj "/C=US/ST=State/L=City/O=ToyShare/OU=IT Department/CN=${DOMAIN}"

# Set proper permissions for SSL certificates
chmod 600 "${SSL_DIR}/privkey.pem"
chmod 644 "${SSL_DIR}/fullchain.pem"

# Create rate limiting configuration
echo "Setting up rate limiting configuration..."
cat > /etc/nginx/conf.d/rate_limit.conf << 'EOF'
# Rate limiting configuration
limit_req_zone $binary_remote_addr zone=req_per_ip:10m rate=50r/s;
limit_req_zone $binary_remote_addr zone=req_per_min:10m rate=600r/m;
limit_req_status 429;
limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;
limit_conn_status 429;
EOF

# Create gzip compression configuration
echo "Setting up gzip compression..."
cat > /etc/nginx/conf.d/gzip.conf << 'EOF'
# Gzip compression configuration
gzip on;
gzip_comp_level 5;
gzip_min_length 256;
gzip_proxied any;
gzip_vary on;
gzip_types
    text/plain
    text/css
    text/javascript
    application/javascript
    application/x-javascript
    application/json
    application/xml
    application/rss+xml
    application/atom+xml
    application/vnd.ms-fontobject
    application/x-font-ttf
    font/opentype
    image/svg+xml;
EOF

# Create nginx site configuration
echo "Creating nginx configuration for ${DOMAIN}..."
cat > "${NGINX_SITES_DIR}/${DOMAIN}" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL configuration
    ssl_certificate ${SSL_DIR}/fullchain.pem;
    ssl_certificate_key ${SSL_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;

    # Proxy to toyexchange Node.js app
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # Serve uploaded files directly from data disk
    location /uploads/ {
        alias ${MOUNT_DIR}/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff;
        
        # Security for uploaded files
        location ~* \.(php|jsp|asp|sh|py|pl|rb)$ {
            deny all;
        }
    }

    # Serve static files from data disk
    location /static/ {
        alias ${MOUNT_DIR}/../static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # API endpoints (if needed)
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable the site
echo "Enabling nginx site..."
ln -sf "${NGINX_SITES_DIR}/${DOMAIN}" "${NGINX_ENABLED_DIR}/${DOMAIN}"

# Remove default site if it exists
if [ -f "${NGINX_ENABLED_DIR}/default" ]; then
    rm -f "${NGINX_ENABLED_DIR}/default"
fi

# Create data directory structure with uploads subdirectory
echo "Setting up data directory structure..."
mkdir -p "${WWW_DATA_DIR}/uploads"
mkdir -p "${WWW_DATA_DIR}/static"
mkdir -p "${WWW_DATA_DIR}/logs"

# Set proper permissions for uploads directory (writable by nodejs app)
chown -R www-data:www-data "${WWW_DATA_DIR}"
chmod -R 755 "${WWW_DATA_DIR}"
chmod 775 "${WWW_DATA_DIR}/uploads"

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Enable and restart nginx
echo "Enabling and restarting nginx..."
systemctl enable nginx
systemctl restart nginx

# Display status
echo "Setup completed successfully!"
echo "=================================="
echo "Domain: ${DOMAIN}"
echo "Nginx status: $(systemctl is-active nginx)"
echo "PM2 status: $(pm2 jlist | jq -r '.[0].pm2_env.status // "unknown"')"
echo "Data directory: ${WWW_DATA_DIR}"
echo "SSL certificate location: ${SSL_DIR}"
echo ""
echo "You can access the application at:"
echo "  HTTP: http://$(curl -s ifconfig.me)/"
echo "  HTTPS: https://$(curl -s ifconfig.me)/"
echo ""
echo "Note: The SSL certificate is self-signed and will show a browser warning."
echo "=================================="
