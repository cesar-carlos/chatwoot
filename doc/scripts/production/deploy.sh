#!/usr/bin/env bash
# Deploy/Update Chatwoot production application
# Location: doc/scripts/production/deploy.sh
# Run as the chatwoot user (not root)
# Usage: sudo -u chatwoot bash doc/scripts/production/deploy.sh

set -e

APP_ROOT="${APP_ROOT:-/home/chatwoot/chatwoot}"
DEPLOY_USER="${DEPLOY_USER:-chatwoot}"
REPO_URL="${REPO_URL:-https://github.com/cesar-carlos/chatwoot.git}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
NODE_HEAP_MB="${NODE_HEAP_MB:-4096}"

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

# 1. Sync code from configured repository
echo ">> 1/8 Pulling latest code..."
if [ -d ".git" ]; then
  git remote set-url origin "$REPO_URL"
  git fetch origin
  git checkout "$DEPLOY_BRANCH"
  git reset --hard "origin/$DEPLOY_BRANCH"
else
  echo "Not a git repository. Skipping git pull."
fi

# 2. Install Ruby dependencies
echo ""
echo ">> 2/8 Installing Ruby dependencies..."
bundle config set without "development test"
bundle install

# 3. Install Node dependencies
echo ""
echo ">> 3/8 Installing Node dependencies..."
pnpm install --ignore-scripts

# 4. Run database migrations
echo ""
echo ">> 4/8 Running database migrations..."
RAILS_ENV=production bundle exec rails db:migrate

# 5. Precompile assets
echo ""
echo ">> 5/8 Precompiling assets..."
NODE_OPTIONS="--max-old-space-size=$NODE_HEAP_MB" RAILS_ENV=production bundle exec rails assets:precompile

# 6. Clear cache
echo ""
echo ">> 6/8 Clearing cache..."
RAILS_ENV=production bundle exec rails tmp:clear

# 7. Ensure storage directory (for Active Storage uploads when ACTIVE_STORAGE_SERVICE=local)
echo ""
echo ">> 7/8 Ensuring storage directory..."
mkdir -p storage tmp/sockets

# 8. Restart services
echo ""
echo ">> 8/8 Restarting services..."
sudo systemctl restart chatwoot-puma
sudo systemctl restart chatwoot-sidekiq

echo ""
echo "== Deploy complete =="
echo ""
echo "Repository: $REPO_URL"
echo "Branch: $DEPLOY_BRANCH"
echo ""
echo "Check service status:"
echo "  sudo systemctl status chatwoot-puma"
echo "  sudo systemctl status chatwoot-sidekiq"
echo ""
echo "View logs:"
echo "  sudo journalctl -u chatwoot-puma -f"
echo "  sudo journalctl -u chatwoot-sidekiq -f"
echo ""
