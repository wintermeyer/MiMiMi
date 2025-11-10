#!/bin/bash
set -e

DEPLOY_USER="mimimi"
DEPLOY_DIR="/var/www/mimimi"
RELEASE_DIR="$DEPLOY_DIR/releases/$(date +%Y%m%d%H%M%S)"
CURRENT_LINK="$DEPLOY_DIR/current"
SHARED_DIR="$DEPLOY_DIR/shared"
BACKUP_DIR="$SHARED_DIR/backups"

# Health check configuration
HEALTH_CHECK_URL="http://localhost:4020/health"
HEALTH_CHECK_TIMEOUT=30
HEALTH_CHECK_RETRIES=6

# Rollback function
rollback_deployment() {
    local reason=$1
    echo "❌ Deployment failed: $reason"
    echo "==> Rolling back to previous release..."

    if [ -n "$PREVIOUS_RELEASE" ] && [ -d "$PREVIOUS_RELEASE" ]; then
        echo "==> Restoring previous release: $PREVIOUS_RELEASE"
        ln -sfn "$PREVIOUS_RELEASE" "$CURRENT_LINK"

        echo "==> Restarting application with previous release"
        sudo systemctl restart mimimi

        echo "==> Waiting for application to start..."
        sleep 5

        if systemctl is-active --quiet mimimi; then
            echo "✅ Rollback successful! Application restored to previous version."
        else
            echo "❌ WARNING: Rollback failed! Application is not running."
            echo "    Please investigate manually: sudo journalctl -u mimimi -n 100"
        fi
    else
        echo "❌ WARNING: No previous release found. Manual intervention required."
    fi

    # Remove failed release directory
    if [ -d "$RELEASE_DIR" ]; then
        echo "==> Cleaning up failed release: $RELEASE_DIR"
        rm -rf "$RELEASE_DIR"
    fi

    exit 1
}

# Health check function
check_health() {
    echo "==> Performing health check..."

    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        echo "    Attempt $i/$HEALTH_CHECK_RETRIES..."

        # Check if service is active
        if ! systemctl is-active --quiet mimimi; then
            echo "    Service is not active"
            if [ $i -lt $HEALTH_CHECK_RETRIES ]; then
                sleep 5
                continue
            else
                return 1
            fi
        fi

        # Check HTTP endpoint
        if curl -f -s --max-time "$HEALTH_CHECK_TIMEOUT" "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
            echo "✅ Health check passed!"
            return 0
        else
            echo "    Health check failed"
            if [ $i -lt $HEALTH_CHECK_RETRIES ]; then
                sleep 5
            else
                return 1
            fi
        fi
    done

    return 1
}

# Store previous release for rollback
if [ -L "$CURRENT_LINK" ]; then
    PREVIOUS_RELEASE=$(readlink -f "$CURRENT_LINK")
    echo "==> Previous release: $PREVIOUS_RELEASE"
else
    PREVIOUS_RELEASE=""
    echo "==> No previous release found (first deployment)"
fi

echo "==> Creating release directory: $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "==> Extracting release tarball"
tar -xzf _build/prod/mimimi-*.tar.gz -C "$RELEASE_DIR"

echo "==> Linking shared environment"
ln -sf "$SHARED_DIR/.env" "$RELEASE_DIR/.env"

# Backup database before migrations
# Set ENABLE_PREDEPLOY_BACKUP=false in .env to skip backups for large databases
set -a
source "$SHARED_DIR/.env"
set +a

ENABLE_PREDEPLOY_BACKUP="${ENABLE_PREDEPLOY_BACKUP:-true}"

if [ "$ENABLE_PREDEPLOY_BACKUP" = "true" ]; then
    echo "==> Creating database backup before migrations..."
    BACKUP_FILE="$BACKUP_DIR/pre-deploy-$(date +%Y%m%d%H%M%S).dump"

    # Use custom format for faster backup/restore and better compression
    if pg_dump -U mimimi \
        --format=custom \
        --compress=6 \
        --file="$BACKUP_FILE" \
        mimimi_prod 2>/dev/null; then

        # Verify backup is not empty
        if [ -s "$BACKUP_FILE" ]; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            echo "✅ Database backup created: $BACKUP_FILE ($BACKUP_SIZE)"
        else
            echo "⚠️  Warning: Backup file is empty (continuing anyway)"
            rm -f "$BACKUP_FILE"
        fi
    else
        echo "⚠️  Warning: Database backup failed (continuing anyway)"
    fi
else
    echo "ℹ️  Pre-deployment backup skipped (ENABLE_PREDEPLOY_BACKUP=false)"
    echo "   Make sure you have another backup strategy in place!"
fi

echo "==> Running database migrations"
cd "$RELEASE_DIR"
set -a  # automatically export all variables
source "$SHARED_DIR/.env"
set +a  # stop automatically exporting

if ! ./bin/migrate; then
    rollback_deployment "Database migration failed"
fi

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

# Perform comprehensive health check
if ! check_health; then
    rollback_deployment "Health check failed"
fi

echo "✅ Deployment successful!"

# Clean up old releases (keep last 5)
echo "==> Cleaning up old releases..."
cd "$DEPLOY_DIR/releases"
ls -t | tail -n +6 | xargs -r rm -rf

# Clean up old pre-deploy backups (keep last 10)
echo "==> Cleaning up old pre-deploy backups..."
cd "$BACKUP_DIR"
# Clean both old format (.sql.gz) and new format (.dump)
ls -t pre-deploy-*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
ls -t pre-deploy-*.dump 2>/dev/null | tail -n +11 | xargs -r rm -f

echo "==> Deployment complete at $(date)"
