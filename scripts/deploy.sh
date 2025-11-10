#!/bin/bash
set -e

# Hybrid Deployment Script with Hot Code Upgrade Support
# Attempts hot code upgrade first, falls back to cold deploy if needed

DEPLOY_USER="pmg"
DEPLOY_DIR="/var/www/pmg"
RELEASE_DIR="$DEPLOY_DIR/releases/$(date +%Y%m%d%H%M%S)"
CURRENT_LINK="$DEPLOY_DIR/current"
SHARED_DIR="$DEPLOY_DIR/shared"
HOT_UPGRADES_DIR="$SHARED_DIR/hot-upgrades"
DEPLOYMENT_VERSION="$(date +%Y%m%d%H%M%S)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}==>${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}==>${NC} $1"
}

log_error() {
    echo -e "${RED}==>${NC} $1"
}

# Detect if hot upgrade is suitable
should_use_hot_upgrade() {
    # Check if hot upgrade is enabled
    if [ ! -d "$HOT_UPGRADES_DIR" ]; then
        log_warn "Hot upgrades directory not found, using cold deploy"
        return 1
    fi

    # Check if application is running
    if ! sudo systemctl is-active --quiet pmg; then
        log_warn "Application is not running, using cold deploy"
        return 1
    fi

    # Check if there are any pending migrations
    # Parse the release tarball to check for new migrations
    if has_pending_migrations; then
        log_warn "Pending database migrations detected, using cold deploy"
        return 1
    fi

    # Check commit message for cold deploy indicators
    if git log -1 --pretty=%B | grep -qiE '\[cold-deploy\]|\[restart\]|\[supervision\]'; then
        log_warn "Commit message indicates cold deploy required"
        return 1
    fi

    return 0
}

has_pending_migrations() {
    # Extract the release to a temp directory to check for new migrations
    local temp_dir=$(mktemp -d)
    tar -xzf _build/prod/mimimi-*.tar.gz -C "$temp_dir" 2>/dev/null || return 0

    # Get the list of migrations from the new release
    local new_migrations=$(find "$temp_dir" -path "*/priv/repo/migrations/*.exs" 2>/dev/null | wc -l)

    # Get the list of migrations from the current release (if it exists)
    local old_migrations=0
    if [ -d "$CURRENT_LINK" ]; then
        old_migrations=$(find "$CURRENT_LINK" -path "*/priv/repo/migrations/*.exs" 2>/dev/null | wc -l)
    fi

    rm -rf "$temp_dir"

    # If new migrations exist, we need a cold deploy
    if [ "$new_migrations" -gt "$old_migrations" ]; then
        return 0  # Has migrations
    else
        return 1  # No migrations
    fi
}

perform_hot_upgrade() {
    log_info "Starting HOT CODE UPGRADE (zero downtime)"

    # Create hot upgrades directory structure
    local version_dir="$HOT_UPGRADES_DIR/$DEPLOYMENT_VERSION"
    mkdir -p "$version_dir"

    # Extract beam files from release tarball
    log_info "Extracting beam files from release..."
    local temp_extract=$(mktemp -d)
    tar -xzf _build/prod/mimimi-*.tar.gz -C "$temp_extract"

    # Find and copy all beam files
    find "$temp_extract" -name "*.beam" -type f | while read beam_file; do
        # Preserve directory structure relative to lib/
        relative_path=$(echo "$beam_file" | sed "s|$temp_extract/||")
        target_dir="$version_dir/$(dirname "$relative_path")"
        mkdir -p "$target_dir"
        cp "$beam_file" "$version_dir/$relative_path"
    done

    rm -rf "$temp_extract"

    # Create metadata file
    log_info "Creating deployment metadata..."
    cat > "$HOT_UPGRADES_DIR/current.json" << EOF
{
  "version": "$DEPLOYMENT_VERSION",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_sha": "$(git rev-parse HEAD)",
  "git_branch": "$(git rev-parse --abbrev-ref HEAD)"
}
EOF

    log_info "Waiting for application to detect and apply hot upgrade..."
    sleep 3

    # Verify the upgrade was applied by checking logs
    if sudo journalctl -u pmg --since "10 seconds ago" | grep -q "\[HotDeploy\].*completed successfully"; then
        log_info "✅ Hot code upgrade completed successfully!"

        # Clean up old hot upgrade versions (keep last 5)
        cd "$HOT_UPGRADES_DIR"
        ls -t | grep -v "current.json" | tail -n +6 | xargs -r rm -rf

        return 0
    else
        log_error "Hot upgrade did not complete successfully"
        log_warn "Falling back to cold deploy..."
        return 1
    fi
}

perform_cold_deploy() {
    log_info "Starting COLD DEPLOY (with restart)"

    log_info "Creating release directory: $RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"

    log_info "Extracting release tarball"
    tar -xzf _build/prod/mimimi-*.tar.gz -C "$RELEASE_DIR"

    log_info "Linking shared environment"
    ln -sf "$SHARED_DIR/.env" "$RELEASE_DIR/.env"

    log_info "Running database migrations"
    cd "$RELEASE_DIR"
    set -a  # automatically export all variables
    source "$SHARED_DIR/.env"
    set +a  # stop automatically exporting
    ./bin/migrate

    log_info "Updating current symlink"
    ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"

    log_info "Creating static files symlink"
    # Find the actual static files directory (handles version changes)
    STATIC_DIR=$(find "$RELEASE_DIR/lib" -type d -name "priv" | head -n1)
    if [ -n "$STATIC_DIR" ]; then
        ln -sfn "$STATIC_DIR/static" "$SHARED_DIR/static"
    fi

    log_info "Restarting application"
    sudo systemctl restart pmg

    log_info "Waiting for application to start..."
    sleep 5

    log_info "Checking application status"
    if sudo systemctl is-active --quiet pmg; then
        log_info "✅ Cold deployment successful!"

        # Clean up old releases (keep last 5)
        cd "$DEPLOY_DIR/releases"
        ls -t | tail -n +6 | xargs -r rm -rf

        return 0
    else
        log_error "❌ Application failed to start, rolling back..."
        # Rollback logic would go here
        return 1
    fi
}

# Main deployment logic
main() {
    log_info "=== Hybrid Deployment System ==="
    log_info "Analyzing deployment requirements..."

    # Determine deployment strategy
    if should_use_hot_upgrade; then
        log_info "✨ Hot code upgrade is suitable"

        if perform_hot_upgrade; then
            log_info "🎉 Deployment completed via hot code upgrade!"
            exit 0
        else
            log_warn "Hot upgrade failed, attempting cold deploy..."
            perform_cold_deploy
            exit $?
        fi
    else
        log_info "🔄 Using cold deploy strategy"
        perform_cold_deploy
        exit $?
    fi
}

# Run main function
main
