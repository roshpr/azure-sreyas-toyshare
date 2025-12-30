#!/bin/bash
# Setup script for ToyShare nginx and SSL configuration
# This script sets up nginx with self-signed SSL certificate for toy-share.org

set -e

echo "Starting ToyShare nginx and SSL setup..."

# Configuration variables
DOMAIN="toy-share.org"
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
SSL_DIR="/etc/nginx/ssl/${DOMAIN}"
WWW_DATA_DIR="/www/data"

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
echo "Creating nginx site configuration for ${DOMAIN}..."
cat > "${NGINX_SITES_DIR}/${DOMAIN}" << EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    # SSL configuration
    ssl_certificate ${SSL_DIR}/fullchain.pem;
    ssl_certificate_key ${SSL_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:HIGH:!aNULL:!MD5';

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # Rate limiting
    limit_req zone=req_per_ip burst=20 nodelay;
    limit_req zone=req_per_min burst=200;
    limit_conn conn_per_ip 20;
    client_max_body_size 50m;
    client_header_timeout 10s;
    client_body_timeout 15s;
    send_timeout 30s;
    keepalive_timeout 20s;

    # Node.js application proxy
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Static file serving from /www/data
    location /data/ {
        alias ${WWW_DATA_DIR}/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        
        # Cache static files
        expires 1y;
        add_header Cache-Control "public, immutable";
        
        # Security for file uploads
        location ~* \.(php|jsp|asp|sh|py|pl|rb)$ {
            deny all;
        }
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

# Create data directory structure
echo "Setting up data directory structure..."
mkdir -p "${WWW_DATA_DIR}/uploads"
mkdir -p "${WWW_DATA_DIR}/static"
mkdir -p "${WWW_DATA_DIR}/logs"

# Set proper permissions
chown -R www-data:www-data "${WWW_DATA_DIR}"
chmod -R 755 "${WWW_DATA_DIR}"

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Enable and restart nginx
echo "Enabling and restarting nginx..."
systemctl enable nginx
systemctl restart nginx

# Install Node.js and PM2 for the application
echo "Installing Node.js and PM2..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

nvm install 22
nvm use 22
npm install -g pm2

# Create a simple Node.js application placeholder
echo "Creating placeholder Node.js application..."
mkdir -p /opt/toyshare
cat > /opt/toyshare/app.js << 'EOF'
const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());
app.use(express.static('/www/data'));

// Health endpoint
app.get('/health', (req, res) => {
    res.status(200).send('healthy\n');
});

// API endpoints
app.get('/api/status', (req, res) => {
    res.json({
        status: 'running',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

// File listing API
app.get('/api/files', (req, res) => {
    const dataDir = '/www/data';
    try {
        const files = fs.readdirSync(dataDir, { withFileTypes: true })
            .filter(dirent => dirent.isFile())
            .map(dirent => dirent.name);
        res.json({ files });
    } catch (error) {
        res.status(500).json({ error: 'Unable to read files' });
    }
});

// Serve static files from /www/data
app.use('/data', express.static('/www/data'));

// Default route
app.get('/', (req, res) => {
    res.send(`
        <html>
            <head><title>ToyShare</title></head>
            <body>
                <h1>Welcome to ToyShare</h1>
                <p>This is the ToyShare Node.js application.</p>
                <p><a href="/health">Health Check</a></p>
                <p><a href="/api/status">API Status</a></p>
                <p><a href="/data">Browse Files</a></p>
            </body>
        </html>
    `);
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`ToyShare server running on port ${PORT}`);
});
EOF

# Install Node.js dependencies
cd /opt/toyshare
npm init -y
npm install express

# Create PM2 configuration file
cat > /opt/toyshare/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'toyshare',
    script: 'app.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF

# Start the application with PM2
echo "Starting ToyShare application with PM2..."
pm2 start ecosystem.config.js
pm2 save
pm2 startup

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
