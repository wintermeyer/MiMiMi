#!/bin/bash
# Debug script for static file serving issues
# Run this on the production server to diagnose why static files aren't being served

set -e

echo "=== Static Files Debugging Script ==="
echo ""

DEPLOY_DIR="/var/www/mimimi"
CURRENT_DIR="$DEPLOY_DIR/current"
SHARED_STATIC="$DEPLOY_DIR/shared/static"

echo "1. Checking current release symlink..."
if [ -L "$CURRENT_DIR" ]; then
    CURRENT_RELEASE=$(readlink -f "$CURRENT_DIR")
    echo "   ✓ Current release: $CURRENT_RELEASE"
else
    echo "   ✗ ERROR: Current symlink not found!"
    exit 1
fi

echo ""
echo "2. Checking for priv/static in release..."
STATIC_DIR=$(find "$CURRENT_RELEASE/lib" -type d -name "priv" 2>/dev/null | head -n1)
if [ -n "$STATIC_DIR" ]; then
    echo "   ✓ Found priv directory: $STATIC_DIR"
    ACTUAL_STATIC="$STATIC_DIR/static"

    if [ -d "$ACTUAL_STATIC" ]; then
        echo "   ✓ Static directory exists: $ACTUAL_STATIC"
    else
        echo "   ✗ ERROR: Static directory not found in release!"
        exit 1
    fi
else
    echo "   ✗ ERROR: Could not find priv directory in release!"
    exit 1
fi

echo ""
echo "3. Checking shared/static symlink..."
if [ -L "$SHARED_STATIC" ]; then
    SYMLINK_TARGET=$(readlink -f "$SHARED_STATIC")
    echo "   ✓ Symlink exists: $SHARED_STATIC -> $SYMLINK_TARGET"

    if [ "$SYMLINK_TARGET" = "$ACTUAL_STATIC" ]; then
        echo "   ✓ Symlink points to correct location"
    else
        echo "   ⚠ WARNING: Symlink points to wrong location!"
        echo "      Expected: $ACTUAL_STATIC"
        echo "      Actual: $SYMLINK_TARGET"
        echo "   Fixing symlink..."
        ln -sfn "$ACTUAL_STATIC" "$SHARED_STATIC"
        echo "   ✓ Symlink fixed"
    fi
else
    echo "   ✗ ERROR: Symlink not found! Creating it..."
    ln -sfn "$ACTUAL_STATIC" "$SHARED_STATIC"
    echo "   ✓ Symlink created"
fi

echo ""
echo "4. Checking BMBFSFJ logo file..."
LOGO_FILE="BMBFSFJ_de_v1__Web_farbig.webp"
LOGO_PATTERN="BMBFSFJ_de_v1__Web_farbig-*.webp"

# Check for original file
if [ -f "$ACTUAL_STATIC/images/$LOGO_FILE" ]; then
    echo "   ✓ Found original logo: images/$LOGO_FILE"
fi

# Check for digested files
DIGESTED_COUNT=$(find "$ACTUAL_STATIC/images" -name "$LOGO_PATTERN" 2>/dev/null | wc -l)
if [ "$DIGESTED_COUNT" -gt 0 ]; then
    echo "   ✓ Found $DIGESTED_COUNT digested logo file(s):"
    find "$ACTUAL_STATIC/images" -name "$LOGO_PATTERN" -exec basename {} \; | sed 's/^/      /'
else
    echo "   ✗ WARNING: No digested logo files found!"
fi

echo ""
echo "5. Checking file permissions..."
echo "   Shared static directory:"
ls -lad "$SHARED_STATIC" 2>/dev/null || echo "   ✗ Directory not accessible"

echo "   Images directory:"
if [ -d "$SHARED_STATIC/images" ]; then
    ls -lad "$SHARED_STATIC/images"
    echo ""
    echo "   Logo files:"
    ls -la "$SHARED_STATIC/images" | grep -i bmbfsfj || echo "   ✗ No logo files found"
else
    echo "   ✗ Images directory not found at $SHARED_STATIC/images"
fi

echo ""
echo "6. Checking cache_manifest.json..."
CACHE_MANIFEST="$ACTUAL_STATIC/cache_manifest.json"
if [ -f "$CACHE_MANIFEST" ]; then
    echo "   ✓ Cache manifest exists"
    if grep -q "BMBFSFJ" "$CACHE_MANIFEST"; then
        echo "   ✓ Logo is in cache manifest"
        echo "   Logo entries:"
        grep "BMBFSFJ" "$CACHE_MANIFEST" | head -3
    else
        echo "   ✗ WARNING: Logo NOT in cache manifest!"
    fi
else
    echo "   ✗ ERROR: Cache manifest not found!"
fi

echo ""
echo "7. Testing file access..."
if [ -L "$SHARED_STATIC" ]; then
    TEST_FILE=$(find "$SHARED_STATIC/images" -name "$LOGO_PATTERN" -type f | head -1)
    if [ -n "$TEST_FILE" ]; then
        echo "   Testing read access to: $TEST_FILE"
        if head -c 10 "$TEST_FILE" > /dev/null 2>&1; then
            FILE_SIZE=$(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null)
            echo "   ✓ File is readable (size: $FILE_SIZE bytes)"
        else
            echo "   ✗ ERROR: Cannot read file!"
        fi
    fi
fi

echo ""
echo "8. Checking nginx configuration..."
if command -v nginx > /dev/null 2>&1; then
    echo "   Nginx config locations for static files:"
    sudo grep -n "static" /etc/nginx/sites-available/mimimi 2>/dev/null | grep -v "#" || echo "   ⚠ Could not read nginx config (try with sudo)"

    echo ""
    echo "   Testing nginx config:"
    sudo nginx -t 2>&1 | tail -2
else
    echo "   ⚠ Nginx not found in PATH"
fi

echo ""
echo "=== Diagnostic Complete ==="
echo ""
echo "Next steps if issues found:"
echo "1. If symlink was fixed, restart nginx: sudo systemctl restart nginx"
echo "2. If files are missing, redeploy: git push (triggers GitHub Actions)"
echo "3. If permissions are wrong, check nginx user: ps aux | grep nginx"
echo "4. Check nginx error logs: sudo tail -100 /var/log/nginx/error.log"
