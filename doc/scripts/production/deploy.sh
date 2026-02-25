#!/usr/bin/env bash
# Deploy/Update Chatwoot production application
# Location: doc/scripts/production/deploy.sh
# Run as the chatwoot user (not root)
# Usage: sudo -u chatwoot bash doc/scripts/production/deploy.sh

set -e

APP_ROOT="/home/chatwoot/chatwoot"
DEPLOY_USER="chatwoot"

# Check if running as correct user
if [ "$(whoami)" != "$DEPLOY_USER" ]; then
  echo "ERROR: This script must be run as the $DEPLOY_USER user"
  echo "Use: sudo -u $DEPLOY_USER bash $0"
  exit 1
fi

# Check if app directory exists
if [ ! -d "$APP_ROOT" ]; then
  echo "ERROR: Application directory not found: $APP_ROOT"
  exit 1
fi

cd "$APP_ROOT"

# Initialize rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "== Deploying Chatwoot =="
echo ""

# 1. Pull latest code
echo ">> 1/7 Pulling latest code..."
if [ -d ".git" ]; then
  git fetch origin
  git pull origin main
else
  echo "Not a git repository. Skipping git pull."
fi

# 2. Install Ruby dependencies
echo ""
echo ">> 2/7 Installing Ruby dependencies..."
bundle install --without development test

# 3. Install Node dependencies
echo ""
echo ">> 3/7 Installing Node dependencies..."
pnpm install --prod

# 4. Run database migrations
echo ""
echo ">> 4/7 Running database migrations..."
RAILS_ENV=production bundle exec rails db:migrate

# 5. Precompile assets
echo ""
echo ">> 5/7 Precompiling assets..."
RAILS_ENV=production bundle exec rails assets:precompile

# 6. Clear cache
echo ""
echo ">> 6/7 Clearing cache..."
RAILS_ENV=production bundle exec rails tmp:clear

# 7. Restart services
echo ""
echo ">> 7/7 Restarting services..."
sudo systemctl restart chatwoot-puma
sudo systemctl restart chatwoot-sidekiq

echo ""
echo "== Deploy complete =="
echo ""
echo "Check service status:"
echo "  sudo systemctl status chatwoot-puma"
echo "  sudo systemctl status chatwoot-sidekiq"
echo ""
echo "View logs:"
echo "  sudo journalctl -u chatwoot-puma -f"
echo "  sudo journalctl -u chatwoot-sidekiq -f"
echo ""
