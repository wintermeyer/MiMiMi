#!/bin/bash

# Rollback utility for MiMiMi Phoenix Application
# This script helps you rollback to a previous release

set -e

DEPLOY_DIR="/var/www/mimimi"
CURRENT_LINK="$DEPLOY_DIR/current"
RELEASES_DIR="$DEPLOY_DIR/releases"
BACKUP_DIR="$DEPLOY_DIR/shared/backups"
APP_NAME="mimimi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo "ℹ️  $1"
}

# Get current release
get_current_release() {
    if [ -L "$CURRENT_LINK" ]; then
        readlink -f "$CURRENT_LINK"
    else
        echo ""
    fi
}

# List available releases
list_releases() {
    echo ""
    echo "Available releases:"
    echo "==================="

    local current_release=$(get_current_release)
    local count=0

    cd "$RELEASES_DIR"
    for release in $(ls -t); do
        count=$((count + 1))
        if [ "$RELEASES_DIR/$release" = "$current_release" ]; then
            print_success "$count. $release (CURRENT)"
        else
            echo "$count. $release"
        fi
    done

    echo ""
}

# List available database backups
list_backups() {
    echo ""
    echo "Available database backups:"
    echo "==========================="

    local count=0

    cd "$BACKUP_DIR"
    # List both .dump (custom format) and .sql.gz (old format) files
    if ls *.dump *.sql.gz 1> /dev/null 2>&1; then
        for backup in $(ls -t *.dump *.sql.gz 2>/dev/null); do
            count=$((count + 1))
            local size=$(du -h "$backup" | cut -f1)
            local format=""
            if [[ "$backup" == *.dump ]]; then
                format="(custom)"
            else
                format="(gzipped)"
            fi
            echo "$count. $backup - $size $format"
        done
    else
        print_warning "No database backups found"
    fi

    echo ""
}

# Rollback to specific release
rollback_to_release() {
    local release_dir=$1

    if [ ! -d "$release_dir" ]; then
        print_error "Release directory does not exist: $release_dir"
        exit 1
    fi

    local current_release=$(get_current_release)

    if [ "$release_dir" = "$current_release" ]; then
        print_warning "Already on this release. Restarting service..."
        sudo systemctl restart $APP_NAME
        return 0
    fi

    print_info "Rolling back from: $current_release"
    print_info "Rolling back to:   $release_dir"
    echo ""

    read -p "Are you sure you want to rollback? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_warning "Rollback cancelled"
        exit 0
    fi

    echo ""
    print_info "Updating current symlink..."
    ln -sfn "$release_dir" "$CURRENT_LINK"

    print_info "Restarting application..."
    sudo systemctl restart $APP_NAME

    echo ""
    print_info "Waiting for application to start..."
    sleep 5

    if systemctl is-active --quiet $APP_NAME; then
        print_success "Rollback successful! Application is running."
        echo ""
        print_info "Checking application health..."
        if curl -f -s --max-time 10 http://localhost:4019/health > /dev/null 2>&1; then
            print_success "Application health check passed!"
        else
            print_warning "Health check failed. Check logs: sudo journalctl -u $APP_NAME -n 50"
        fi
    else
        print_error "Application failed to start!"
        print_info "Check logs: sudo journalctl -u $APP_NAME -n 50"
        exit 1
    fi
}

# Restore database backup
restore_backup() {
    local backup_file=$1

    if [ ! -f "$backup_file" ]; then
        print_error "Backup file does not exist: $backup_file"
        exit 1
    fi

    print_warning "WARNING: This will restore the database from backup."
    print_warning "All current data will be replaced with the backup data."
    echo ""
    read -p "Are you ABSOLUTELY sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_warning "Database restore cancelled"
        exit 0
    fi

    echo ""
    print_info "Stopping application..."
    sudo systemctl stop $APP_NAME

    print_info "Restoring database from: $backup_file"

    # Detect backup format and use appropriate restore method
    if [[ "$backup_file" == *.dump ]]; then
        # Custom format backup - use pg_restore
        print_info "Detected custom format backup (.dump)"
        if pg_restore -U mimimi \
            --dbname=mimimi_prod \
            --clean \
            --if-exists \
            --no-owner \
            --no-acl \
            "$backup_file" 2>/dev/null; then
            print_success "Database restored successfully!"
        else
            print_error "Database restore failed!"
            sudo systemctl start $APP_NAME
            exit 1
        fi
    elif [[ "$backup_file" == *.sql.gz ]]; then
        # Gzipped SQL format - use gunzip + psql
        print_info "Detected gzipped SQL format (.sql.gz)"
        if gunzip -c "$backup_file" | psql -U mimimi -d mimimi_prod 2>/dev/null; then
            print_success "Database restored successfully!"
        else
            print_error "Database restore failed!"
            sudo systemctl start $APP_NAME
            exit 1
        fi
    else
        print_error "Unknown backup format: $backup_file"
        print_info "Supported formats: .dump (custom), .sql.gz (gzipped SQL)"
        sudo systemctl start $APP_NAME
        exit 1
    fi

    print_info "Starting application..."
    sudo systemctl start $APP_NAME

    sleep 5

    if systemctl is-active --quiet $APP_NAME; then
        print_success "Application started successfully!"
    else
        print_error "Application failed to start!"
        print_info "Check logs: sudo journalctl -u $APP_NAME -n 50"
        exit 1
    fi
}

# Interactive menu
show_menu() {
    echo "============================================"
    echo "   MiMiMi Rollback Utility"
    echo "============================================"
    echo ""
    echo "1. Rollback to previous release"
    echo "2. Rollback to specific release"
    echo "3. List all releases"
    echo "4. Restore database from backup"
    echo "5. List database backups"
    echo "6. Check current status"
    echo "7. Exit"
    echo ""
}

# Main program
main() {
    # Check if running with correct permissions
    if [ ! -d "$DEPLOY_DIR" ]; then
        print_error "Deployment directory not found: $DEPLOY_DIR"
        print_info "Are you running this on the production server?"
        exit 1
    fi

    # If arguments provided, execute directly
    if [ "$1" = "previous" ]; then
        # Rollback to previous release
        cd "$RELEASES_DIR"
        local current_release=$(get_current_release)
        local previous_release=$(ls -t | grep -v "$(basename "$current_release")" | head -n 1)

        if [ -z "$previous_release" ]; then
            print_error "No previous release found"
            exit 1
        fi

        rollback_to_release "$RELEASES_DIR/$previous_release"
        exit 0
    elif [ "$1" = "list" ]; then
        list_releases
        exit 0
    elif [ "$1" = "backups" ]; then
        list_backups
        exit 0
    fi

    # Interactive mode
    while true; do
        show_menu
        read -p "Select an option (1-7): " choice

        case $choice in
            1)
                # Rollback to previous release
                cd "$RELEASES_DIR"
                local current_release=$(get_current_release)
                local previous_release=$(ls -t | grep -v "$(basename "$current_release")" | head -n 1)

                if [ -z "$previous_release" ]; then
                    print_error "No previous release found"
                    echo ""
                    continue
                fi

                echo ""
                print_info "Previous release: $previous_release"
                rollback_to_release "$RELEASES_DIR/$previous_release"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                # Rollback to specific release
                list_releases
                read -p "Enter release number: " release_num

                cd "$RELEASES_DIR"
                local release=$(ls -t | sed -n "${release_num}p")

                if [ -z "$release" ]; then
                    print_error "Invalid release number"
                    echo ""
                    continue
                fi

                rollback_to_release "$RELEASES_DIR/$release"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                # List all releases
                list_releases
                read -p "Press Enter to continue..."
                ;;
            4)
                # Restore database from backup
                list_backups
                read -p "Enter backup number to restore: " backup_num

                cd "$BACKUP_DIR"
                local backup=$(ls -t *.sql.gz 2>/dev/null | sed -n "${backup_num}p")

                if [ -z "$backup" ]; then
                    print_error "Invalid backup number"
                    echo ""
                    continue
                fi

                restore_backup "$BACKUP_DIR/$backup"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                # List database backups
                list_backups
                read -p "Press Enter to continue..."
                ;;
            6)
                # Check current status
                echo ""
                local current_release=$(get_current_release)
                print_info "Current release: $(basename "$current_release")"
                echo ""

                if systemctl is-active --quiet $APP_NAME; then
                    print_success "Application is running"
                else
                    print_error "Application is not running"
                fi

                echo ""
                print_info "Recent logs:"
                sudo journalctl -u $APP_NAME -n 10 --no-pager
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
                # Exit
                echo ""
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-7."
                echo ""
                ;;
        esac
    done
}

# Run main program
main "$@"
