#!/bin/bash
set -e

DEPLOY_USER="mimimi"
DEPLOY_DIR="/var/www/mimimi"
RELEASE_DIR="$DEPLOY_DIR/releases/$(date +%Y%m%d%H%M%S)"
CURRENT_LINK="$DEPLOY_DIR/current"
SHARED_DIR="$DEPLOY_DIR/shared"

echo "==> Creating release directory: $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "==> Extracting release tarball"
tar -xzf _build/prod/mimimi-*.tar.gz -C "$RELEASE_DIR"

echo "==> Linking shared environment"
ln -sf "$SHARED_DIR/.env" "$RELEASE_DIR/.env"

echo "==> Running database migrations"
cd "$RELEASE_DIR"
set -a  # automatically export all variables
source "$SHARED_DIR/.env"
set +a  # stop automatically exporting
./bin/migrate

echo "==> Updating current symlink"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

echo "==> Creating static files symlink"
# Find the actual static files directory (handles version changes)
STATIC_DIR=$(find "$RELEASE_DIR/lib" -type d -name "priv" | head -n1)
if [ -n "$STATIC_DIR" ]; then
    ln -sfn "$STATIC_DIR/static" "$SHARED_DIR/static"
fi

echo "==> Restarting application"
sudo systemctl restart mimimi

echo "==> Waiting for application to start..."
sleep 5

echo "==> Checking application status"
if sudo systemctl is-active --quiet mimimi; then
    echo "✅ Deployment successful!"

    # Clean up old releases (keep last 5)
    cd "$DEPLOY_DIR/releases"
    ls -t | tail -n +6 | xargs -r rm -rf
else
    echo "❌ Application failed to start, rolling back..."
    exit 1
fi
