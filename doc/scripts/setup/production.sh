#!/usr/bin/env bash
# Setup Chatwoot production environment (native, no Docker)
# OS: Ubuntu 24.04 LTS
# Architecture: Nginx (reverse proxy) + Puma (app server) + Sidekiq (jobs) + PostgreSQL + Redis
# Process management: systemd

set -e

echo "== Chatwoot native production setup =="
echo ""
echo "This script will:"
echo "  1. Install system dependencies (PostgreSQL 16, Redis, Nginx)"
echo "  2. Install Ruby 3.4.4 and Node 24"
echo "  3. Create a dedicated chatwoot user"
echo "  4. Configure Nginx as reverse proxy"
echo "  5. Set up systemd services for Puma and Sidekiq"
echo "  6. Configure SSL with Let's Encrypt (optional)"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

# Configuration - EDIT THESE
DOMAIN="${DOMAIN:-}"
DEPLOY_USER="chatwoot"
DEPLOY_GROUP="chatwoot"
APP_ROOT="/home/$DEPLOY_USER/chatwoot"
RUBY_VERSION="3.4.4"
NODE_VERSION="24"

if [ -z "$DOMAIN" ]; then
  read -p "Enter your domain (e.g., chat.example.com): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo "ERROR: Domain is required"
    exit 1
  fi
fi

echo "Installing Chatwoot for domain: $DOMAIN"
echo ""

# 1. System dependencies
echo ">> 1/9 Installing system dependencies..."
apt-get update
apt-get install -y \
  curl git build-essential libpq-dev libssl-dev libreadline-dev \
  zlib1g-dev libyaml-dev libxml2-dev libxslt1-dev libffi-dev \
  libgmp-dev libncurses5-dev libgdbm-dev libgdbm6 \
  libvips imagemagick postgresql-client ffmpeg \
  certbot python3-certbot-nginx nginx ufw

# 2. PostgreSQL 16
echo ""
echo ">> 2/9 Installing PostgreSQL 16..."
if ! command -v psql &>/dev/null || ! psql --version | grep -q 16; then
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
  sh -c 'echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  apt-get update
  apt-get install -y postgresql-16 postgresql-16-pgvector postgresql-contrib
fi
systemctl start postgresql
systemctl enable postgresql

# Create production database user and database
DB_PASSWORD=$(openssl rand -base64 32)
sudo -u postgres psql <<EOF
-- Create user if not exists
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DEPLOY_USER') THEN
    CREATE USER $DEPLOY_USER WITH PASSWORD '$DB_PASSWORD';
  END IF;
END
\$\$;

-- Create database if not exists
SELECT 'CREATE DATABASE chatwoot_production OWNER $DEPLOY_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'chatwoot_production')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE chatwoot_production TO $DEPLOY_USER;
ALTER USER $DEPLOY_USER CREATEDB;
EOF

# 3. Redis
echo ""
echo ">> 3/9 Installing Redis..."
if ! command -v redis-server &>/dev/null; then
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
  apt-get update
  apt-get install -y redis-server
fi

# Configure Redis for production
sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/' /etc/redis/redis.conf
systemctl start redis-server
systemctl enable redis-server

# 4. Create deploy user
echo ""
echo ">> 4/9 Creating deploy user..."
if ! id "$DEPLOY_USER" &>/dev/null; then
  useradd -m -s /bin/bash $DEPLOY_USER
  echo "Created user: $DEPLOY_USER"
fi

# 5. Install rbenv + Ruby for deploy user
echo ""
echo ">> 5/9 Installing Ruby $RUBY_VERSION for $DEPLOY_USER..."
sudo -u $DEPLOY_USER -i bash <<EOF
set -e
if [ ! -d "\$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git \$HOME/.rbenv
  git clone https://github.com/rbenv/ruby-build.git \$HOME/.rbenv/plugins/ruby-build
  echo 'export PATH="\$HOME/.rbenv/bin:\$PATH"' >> \$HOME/.bashrc
  echo 'eval "\$(rbenv init -)"' >> \$HOME/.bashrc
fi
export PATH="\$HOME/.rbenv/bin:\$PATH"
eval "\$(rbenv init -)"
if ! rbenv versions | grep -q $RUBY_VERSION; then
  rbenv install $RUBY_VERSION
fi
rbenv global $RUBY_VERSION
gem install bundler
EOF

# 6. Install Node + pnpm globally
echo ""
echo ">> 6/9 Installing Node $NODE_VERSION..."
if ! command -v node &>/dev/null || [[ $(node -v | cut -d. -f1 | tr -d v) -lt $NODE_VERSION ]]; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
fi
if ! command -v pnpm &>/dev/null; then
  npm install -g pnpm
fi

# 7. Configure Nginx
echo ""
echo ">> 7/9 Configuring Nginx..."

# Generate dhparam for SSL if not exists
if [ ! -f "/etc/ssl/dhparam" ]; then
  echo "Generating DH parameters (this may take a few minutes)..."
  openssl dhparam -out /etc/ssl/dhparam 2048
fi

cat > /etc/nginx/sites-available/chatwoot <<NGINX_CONF
# Nginx configuration for Chatwoot production
# Upstream with keepalive for performance
upstream chatwoot_puma {
  zone upstreams 64K;
  server unix:///home/$DEPLOY_USER/chatwoot/tmp/sockets/puma.sock fail_timeout=0;
  keepalive 32;
}

# WebSocket mapping
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  '' close;
}

# HTTP server - redirect to HTTPS
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN;

  access_log /var/log/nginx/chatwoot_access_80.log;
  error_log /var/log/nginx/chatwoot_error_80.log;

  # Let's Encrypt validation
  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  # Redirect to HTTPS
  return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
  listen 443 ssl http2 reuseport;
  listen [::]:443 ssl http2 reuseport;
  server_name $DOMAIN;

  # *** CRITICAL: Allow headers with underscores (required for Chatwoot) ***
  underscores_in_headers on;

  access_log /var/log/nginx/chatwoot_access_443.log;
  error_log /var/log/nginx/chatwoot_error_443.log;

  root /home/$DEPLOY_USER/chatwoot/public;

  # SSL certificates (will be configured by certbot)
  # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  # Robust SSL configuration
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
  ssl_prefer_server_ciphers off;
  ssl_dhparam /etc/ssl/dhparam;
  ssl_early_data on;
  ssl_buffer_size 4k;
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 1d;

  # Security headers
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  # Upload configuration
  client_max_body_size 100M;
  client_body_timeout 3600s;
  client_header_timeout 3600s;
  client_body_buffer_size 100M;

  # Static assets with caching
  location ~ ^/(packs|rails/active_storage) {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
    try_files \$uri @chatwoot_puma;
  }

  # Active Storage with optimized buffering
  location /rails/active_storage/ {
    proxy_pass http://chatwoot_puma;
    proxy_redirect off;
    proxy_buffering off;
    proxy_request_buffering off;
    
    # Essential headers
    proxy_pass_header Authorization;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    # Extended timeouts for uploads
    client_max_body_size 100M;
    proxy_read_timeout 3600s;
    proxy_connect_timeout 300s;
    proxy_send_timeout 3600s;
  }

  # ActionCable WebSocket endpoint
  location /cable {
    proxy_pass http://chatwoot_puma;
    proxy_redirect off;
    proxy_buffering off;
    proxy_cache off;

    # Essential headers
    proxy_pass_header Authorization;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    # Long timeouts for WebSocket
    proxy_read_timeout 36000s;
    proxy_connect_timeout 300s;
    proxy_send_timeout 36000s;
  }

  # Main application
  location / {
    try_files \$uri @chatwoot_puma;
  }

  location @chatwoot_puma {
    proxy_pass http://chatwoot_puma;
    proxy_redirect off;

    # Essential headers for Chatwoot
    proxy_pass_header Authorization;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host \$server_name;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    # Timeouts (extended for large uploads and long requests)
    client_max_body_size 100M;
    proxy_read_timeout 36000s;
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
  }

  # Let's Encrypt validation
  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  # Error pages
  error_page 500 502 503 504 /500.html;
  location = /500.html {
    root /home/$DEPLOY_USER/chatwoot/public;
  }
}
NGINX_CONF

ln -sf /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# 8. Configure systemd services
echo ""
echo ">> 8/9 Configuring systemd services..."

# Puma service
cat > /etc/systemd/system/chatwoot-puma.service <<SERVICE
[Unit]
Description=Chatwoot Puma Web Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=$DEPLOY_USER
Group=$DEPLOY_GROUP
WorkingDirectory=$APP_ROOT
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=true

# Load environment variables from .env
EnvironmentFile=$APP_ROOT/.env

ExecStart=/home/$DEPLOY_USER/.rbenv/shims/bundle exec puma -C config/puma.rb
ExecReload=/bin/kill -SIGUSR2 \$MAINPID

Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=chatwoot-puma

[Install]
WantedBy=multi-user.target
SERVICE

# Sidekiq service
cat > /etc/systemd/system/chatwoot-sidekiq.service <<SERVICE
[Unit]
Description=Chatwoot Sidekiq Background Jobs
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=$DEPLOY_USER
Group=$DEPLOY_GROUP
WorkingDirectory=$APP_ROOT
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=true

# Load environment variables from .env
EnvironmentFile=$APP_ROOT/.env

ExecStart=/home/$DEPLOY_USER/.rbenv/shims/bundle exec sidekiq -C config/sidekiq.yml

Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=chatwoot-sidekiq

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload

# 9. Firewall configuration
echo ""
echo ">> 9/9 Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

# Generate secure secret key
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Create .env template
echo ""
echo "Creating environment configuration template..."
sudo -u $DEPLOY_USER bash <<EOF
mkdir -p $APP_ROOT
cat > $APP_ROOT/.env.template <<ENV
# === Database ===
POSTGRES_HOST=localhost
POSTGRES_USERNAME=$DEPLOY_USER
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_DATABASE=chatwoot_production

# === Redis ===
REDIS_URL=redis://localhost:6379

# === Rails ===
RAILS_ENV=production
SECRET_KEY_BASE=$SECRET_KEY_BASE
FRONTEND_URL=https://$DOMAIN
FORCE_SSL=true
RAILS_LOG_TO_STDOUT=true

# === Storage (choose one) ===
# Local storage
ACTIVE_STORAGE_SERVICE=local

# S3 storage (recommended for production)
# ACTIVE_STORAGE_SERVICE=amazon
# S3_BUCKET_NAME=your-bucket
# AWS_ACCESS_KEY_ID=your-key
# AWS_SECRET_ACCESS_KEY=your-secret
# AWS_REGION=us-east-1

# === Email (SMTP) ===
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_DOMAIN=example.com
SMTP_USERNAME=notifications@example.com
SMTP_PASSWORD=your-password
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
MAILER_SENDER_EMAIL=notifications@example.com

# === Optional: Third-party integrations ===
# FB_APP_ID=
# FB_APP_SECRET=
# TWITTER_APP_ID=
# TWITTER_CONSUMER_KEY=
# TWITTER_CONSUMER_SECRET=

# === Security ===
RAILS_MAX_THREADS=5
RAILS_MIN_THREADS=5

ENV
EOF

echo ""
echo "== Setup complete =="
echo ""
echo "==================================================================="
echo "IMPORTANT: Next steps to deploy your application"
echo "==================================================================="
echo ""
echo "1. Clone or copy your Chatwoot code to: $APP_ROOT"
echo "   sudo -u $DEPLOY_USER git clone https://github.com/chatwoot/chatwoot.git $APP_ROOT"
echo ""
echo "2. Configure environment variables:"
echo "   sudo -u $DEPLOY_USER cp $APP_ROOT/.env.template $APP_ROOT/.env"
echo "   sudo -u $DEPLOY_USER nano $APP_ROOT/.env"
echo ""
echo "3. Install dependencies and setup database:"
echo "   sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && source ~/.bashrc && bundle install'"
echo "   sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && pnpm install'"
echo "   sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && RAILS_ENV=production bundle exec rails db:prepare'"
echo "   sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && RAILS_ENV=production bundle exec rails db:seed'"
echo ""
echo "4. Precompile assets:"
echo "   sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && RAILS_ENV=production bundle exec rails assets:precompile'"
echo ""
echo "5. Create storage directory (for uploads when ACTIVE_STORAGE_SERVICE=local):"
echo "   sudo -u $DEPLOY_USER mkdir -p $APP_ROOT/storage $APP_ROOT/tmp/sockets"
echo ""
echo "6. Configure SSL with Let's Encrypt:"
echo "   sudo certbot --nginx -d $DOMAIN"
echo ""
echo "7. Start services:"
echo "   sudo systemctl start chatwoot-puma"
echo "   sudo systemctl start chatwoot-sidekiq"
echo "   sudo systemctl enable chatwoot-puma"
echo "   sudo systemctl enable chatwoot-sidekiq"
echo ""
echo "8. Check service status:"
echo "   sudo systemctl status chatwoot-puma"
echo "   sudo systemctl status chatwoot-sidekiq"
echo "   sudo journalctl -u chatwoot-puma -f"
echo ""
echo "==================================================================="
echo "SAVED CREDENTIALS"
echo "==================================================================="
echo ""
echo "PostgreSQL Database:"
echo "  Database: chatwoot_production"
echo "  Username: $DEPLOY_USER"
echo "  Password: $DB_PASSWORD"
echo ""
echo "SAVE THIS PASSWORD - it's also in: $APP_ROOT/.env.template"
echo ""
echo "==================================================================="
echo "USEFUL COMMANDS"
echo "==================================================================="
echo ""
echo "View logs:"
echo "  sudo journalctl -u chatwoot-puma -f"
echo "  sudo journalctl -u chatwoot-sidekiq -f"
echo ""
echo "Restart services:"
echo "  sudo systemctl restart chatwoot-puma"
echo "  sudo systemctl restart chatwoot-sidekiq"
echo ""
echo "Run Rails console:"
echo "  sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && RAILS_ENV=production bundle exec rails console'"
echo ""
echo "Run migrations:"
echo "  sudo -u $DEPLOY_USER bash -c 'cd $APP_ROOT && RAILS_ENV=production bundle exec rails db:migrate'"
echo ""
echo "==================================================================="
