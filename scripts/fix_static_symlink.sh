#!/bin/bash
# Quick fix for broken static file symlink
# Run this on the production server if static files aren't being served

set -e

DEPLOY_DIR="/var/www/mimimi"
CURRENT_DIR="$DEPLOY_DIR/current"
SHARED_STATIC="$DEPLOY_DIR/shared/static"

echo "=== Fixing Static Files Symlink ==="
echo ""

# Check if current release exists
if [ ! -L "$CURRENT_DIR" ]; then
    echo "ERROR: Current release symlink not found at $CURRENT_DIR"
    exit 1
fi

CURRENT_RELEASE=$(readlink -f "$CURRENT_DIR")
echo "Current release: $CURRENT_RELEASE"

# Find the static directory in the release
# Look specifically for mimimi-*/priv to avoid matching dependency libraries
STATIC_DIR=$(find "$CURRENT_RELEASE/lib" -type d -path "*/mimimi-*/priv" 2>/dev/null | head -n1)

if [ -z "$STATIC_DIR" ]; then
    echo "ERROR: Could not find mimimi priv directory in release!"
    echo "Available priv directories:"
    find "$CURRENT_RELEASE/lib" -type d -name "priv" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

ACTUAL_STATIC="$STATIC_DIR/static"

if [ ! -d "$ACTUAL_STATIC" ]; then
    echo "ERROR: Static directory not found at $ACTUAL_STATIC"
    exit 1
fi

echo "Static files location: $ACTUAL_STATIC"

# Check if the symlink exists and is correct
if [ -L "$SHARED_STATIC" ]; then
    CURRENT_TARGET=$(readlink -f "$SHARED_STATIC")
    if [ "$CURRENT_TARGET" = "$ACTUAL_STATIC" ]; then
        echo "✓ Symlink is already correct"
        echo "  $SHARED_STATIC -> $ACTUAL_STATIC"
    else
        echo "⚠ Symlink exists but points to wrong location"
        echo "  Current: $SHARED_STATIC -> $CURRENT_TARGET"
        echo "  Expected: $ACTUAL_STATIC"
        echo "  Fixing..."
        ln -sfn "$ACTUAL_STATIC" "$SHARED_STATIC"
        echo "✓ Symlink updated"
    fi
else
    echo "⚠ Symlink does not exist"
    echo "  Creating: $SHARED_STATIC -> $ACTUAL_STATIC"
    ln -sfn "$ACTUAL_STATIC" "$SHARED_STATIC"
    echo "✓ Symlink created"
fi

# Verify the symlink
if [ -L "$SHARED_STATIC" ] && [ -d "$SHARED_STATIC" ]; then
    echo ""
    echo "✓ Symlink is working correctly"
    echo ""
    echo "Verifying logo file..."
    if find "$SHARED_STATIC/images" -name "BMBFSFJ*.webp" -type f | head -1 | grep -q .; then
        echo "✓ Logo file(s) found in static directory"
        find "$SHARED_STATIC/images" -name "BMBFSFJ*.webp" -type f -exec basename {} \; | sed 's/^/  /'
    else
        echo "⚠ Logo file not found - may need to redeploy"
    fi
else
    echo ""
    echo "ERROR: Symlink verification failed"
    exit 1
fi

echo ""
echo "=== Next Steps ==="
echo "1. Restart nginx: sudo systemctl restart nginx"
echo "2. Test the logo URL in your browser"
echo "3. If still not working, run: ./scripts/debug_static_files.sh"
echo ""
