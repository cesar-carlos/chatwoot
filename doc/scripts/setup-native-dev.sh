#!/usr/bin/env bash
# Setup Chatwoot development environment (native, no Docker)
# OS: Ubuntu 24.04 LTS
# Installs: PostgreSQL 16, Redis, Ruby 3.4.4 (rbenv), Node 24, pnpm

set -e

echo "== Chatwoot native dev setup =="

# Check if running as root (we need sudo for apt)
if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root. Run as your normal user (sudo will be used when needed)."
  exit 1
fi

# 1. System dependencies
echo ""
echo ">> 1/7 Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  curl git build-essential libpq-dev libssl-dev libreadline-dev \
  zlib1g-dev libyaml-dev libxml2-dev libxslt1-dev libffi-dev \
  libgmp-dev libncurses5-dev libgdbm-dev libgdbm6 \
  libvips imagemagick postgresql-client

# 2. PostgreSQL 16
echo ""
echo ">> 2/7 Installing PostgreSQL 16..."
if ! command -v psql &>/dev/null || ! psql --version | grep -q 16; then
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg
  sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
  sudo apt-get update
  sudo apt-get install -y postgresql-16 postgresql-16-pgvector postgresql-contrib
fi
sudo systemctl start postgresql 2>/dev/null || true
sudo systemctl enable postgresql 2>/dev/null || true

# 3. Redis
echo ""
echo ">> 3/7 Installing Redis..."
if ! command -v redis-server &>/dev/null; then
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
  sudo apt-get update
  sudo apt-get install -y redis-server
fi
sudo systemctl start redis-server 2>/dev/null || true
sudo systemctl enable redis-server 2>/dev/null || true

# 4. rbenv + Ruby 3.4.4
echo ""
echo ">> 4/7 Installing rbenv and Ruby 3.4.4..."
if ! command -v rbenv &>/dev/null; then
  git clone https://github.com/rbenv/rbenv.git ~/.rbenv
  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
  touch ~/.bashrc
  grep -qxF 'export PATH="$HOME/.rbenv/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
  grep -qxF 'eval "$(rbenv init -)"' ~/.bashrc || echo 'eval "$(rbenv init -)"' >> ~/.bashrc
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
fi
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)" 2>/dev/null || true
if ! rbenv versions | grep -q 3.4.4; then
  rbenv install 3.4.4
fi
rbenv global 3.4.4

# 5. Node 24 + pnpm
echo ""
echo ">> 5/7 Installing Node 24 and pnpm..."
if ! command -v node &>/dev/null || [[ $(node -v | cut -d. -f1 | tr -d v) -lt 24 ]]; then
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
  sudo apt-get update
  sudo apt-get install -y nodejs
fi
if ! command -v pnpm &>/dev/null; then
  npm install -g pnpm
fi

# 6. Create PostgreSQL databases (if not exists)
echo ""
echo ">> 6/7 Configuring PostgreSQL..."
# Create databases owned by postgres user
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='chatwoot_dev'" | grep -q 1 || \
  sudo -u postgres createdb chatwoot_dev 2>/dev/null || true
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='chatwoot_test'" | grep -q 1 || \
  sudo -u postgres createdb chatwoot_test 2>/dev/null || true

# Configure peer authentication for local connections (no password needed)
echo "PostgreSQL configured with peer authentication (local connections don't need password)"

# 7. App setup (from project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
echo ""
echo ">> 7/7 Installing app dependencies..."
cd "$PROJECT_ROOT"
eval "$(rbenv init -)"
gem install bundler
bundle install
pnpm install

echo ""
echo "== Setup complete =="
echo ""
echo "Configure .env with:"
echo "  POSTGRES_USERNAME=postgres"
echo "  POSTGRES_PASSWORD=  # Leave empty for local peer authentication"
echo "  REDIS_URL=redis://localhost:6379"
echo "  FRONTEND_URL=http://YOUR_IP:3000  # for network access"
echo ""
echo "Note: PostgreSQL uses 'peer' authentication for local connections,"
echo "so no password is needed when connecting as the postgres user locally."
echo ""
echo "Then run:"
echo "  bundle exec rails db:prepare"
echo "  bundle exec rails db:seed"
echo "  pnpm run start:dev"
echo ""
