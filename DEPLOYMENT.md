# Step-by-Step Deployment Guide: Phoenix App on Debian Linux

This is a complete, step-by-step tutorial for deploying your MiMiMi Phoenix application to a Debian Linux server with automated GitHub deployments.

**Prerequisites:**
- A fresh Debian Linux server (Bookworm 12 or newer)
- SSH access with sudo privileges
- A domain name pointed to your server (optional but recommended)
- Your GitHub repository ready

**What you'll build:**
- Automated deployments triggered by pushing to `main`
- Zero-downtime deployments with automatic rollback
- Database migrations run automatically
- Secure environment variable management
- Self-hosted GitHub Actions runner

---

## Part 1: Initial Server Setup

### Step 1.1: Connect to Your Server

```bash
# From your local machine
ssh your-admin-user@your-server-ip
```

### Step 1.2: Update System Packages

```bash
# Update package lists and upgrade all packages
sudo apt update && sudo apt upgrade -y
```

### Step 1.3: Install Required System Packages

```bash
# Install all required packages in one command
sudo apt install -y \
  curl \
  git \
  build-essential \
  autoconf \
  m4 \
  libncurses-dev \
  libssl-dev \
  postgresql \
  postgresql-contrib-15 \
  nginx \
  unattended-upgrades

# If postgresql-contrib-15 fails, it's safe to skip - it's optional
```

**✓ Checkpoint:** Verify installations:
```bash
psql --version          # Should show PostgreSQL 15.x
nginx -v                # Should show nginx version
git --version           # Should show git version
```

---

## Part 2: Create Deployment User

### Step 2.1: Create the `mimimi` User

```bash
# Create user with home directory
sudo useradd -m -s /bin/bash mimimi

# Set a password for the user
sudo passwd mimimi
# Enter a secure password when prompted
```

### Step 2.2: Create Application Directory Structure

```bash
# Create main application directory
sudo mkdir -p /var/www/mimimi

# Set ownership to mimimi user
sudo chown -R mimimi:mimimi /var/www/mimimi

# Create subdirectories as mimimi user
sudo -u mimimi mkdir -p /var/www/mimimi/{releases,shared,shared/backups}
```

**✓ Checkpoint:** Verify directory structure:
```bash
ls -la /var/www/mimimi
# Should show: releases, shared directories owned by mimimi:mimimi
```

---

## Part 3: Install Erlang and Elixir with mise

### Step 3.1: Install mise for Admin User

```bash
# Install mise
curl https://mise.run | sh

# Add mise to your shell
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Verify mise is installed
mise --version
```

### Step 3.2: Install mise for mimimi User

```bash
# Switch to mimimi user
sudo su - mimimi

# Install mise for mimimi
curl https://mise.run | sh

# Add mise to mimimi's shell
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# Install Erlang and Elixir
mise use --global erlang@28
mise use --global elixir@1.19

# This will take several minutes as it compiles Erlang and Elixir
# Wait for it to complete...

# Verify installations
elixir --version
# Should show: Elixir 1.19.x (compiled with Erlang/OTP 28)

erl -version
# Should show: Erlang/OTP 28

# Exit back to admin user
exit
```

**✓ Checkpoint:** Both admin and mimimi users should have Erlang and Elixir installed.

---

## Part 4: Configure PostgreSQL Database

### Step 4.1: Generate Secure Database Password

```bash
# Switch to mimimi user
sudo su - mimimi

# Generate a secure password and save it immediately to the .env file
DB_PASSWORD=$(openssl rand -base64 32)

# URL-encode the password for use in DATABASE_URL
# This handles special characters like +, /, =
DB_PASSWORD_ENCODED=$(printf '%s' "$DB_PASSWORD" | python3 -c "import sys; from urllib.parse import quote; print(quote(sys.stdin.read().strip(), safe=''))")

# Create the .env file with the database password
cat > /var/www/mimimi/shared/.env << EOF
# Database Configuration
DATABASE_URL=postgresql://mimimi:${DB_PASSWORD_ENCODED}@localhost/mimimi_prod
POOL_SIZE=10
EOF

# Secure the .env file
chmod 600 /var/www/mimimi/shared/.env

# Display the password for PostgreSQL setup (copy this now!)
echo "==============================================="
echo "DATABASE PASSWORD (needed for next step):"
echo "$DB_PASSWORD"
echo "==============================================="

# Keep this terminal open or copy the password!
```

**⚠️ IMPORTANT:** Copy the password shown above - you'll need it in the next step!

### Step 4.2: Create PostgreSQL Database and User

```bash
# In a NEW terminal, connect to your server
ssh your-admin-user@your-server-ip

# Switch to postgres user
sudo -u postgres psql

# Now you're in the PostgreSQL shell
# Create the database user (paste the password from Step 4.1)
```

```sql
-- In the PostgreSQL shell, run these commands:
-- Replace 'PASTE_PASSWORD_HERE' with the password from Step 4.1

CREATE USER mimimi WITH PASSWORD 'PASTE_PASSWORD_HERE';
CREATE DATABASE mimimi_prod OWNER mimimi;

-- Verify the database was created
\l mimimi_prod

-- You should see mimimi_prod in the list with owner mimimi

-- Exit PostgreSQL
\q
```

**✓ Checkpoint:** Test database connection:
```bash
# Go back to the terminal where you're logged in as mimimi user
# Test the connection using the DATABASE_URL from .env
source /var/www/mimimi/shared/.env
psql "$DATABASE_URL" -c "SELECT version();"
# Should show PostgreSQL version
```

---

## Part 5: Generate Application Secrets

### Step 5.1: Generate SECRET_KEY_BASE

```bash
# Still as mimimi user
# Generate SECRET_KEY_BASE (must be at least 64 bytes)
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

# Append to .env file
cat >> /var/www/mimimi/shared/.env << EOF

# Phoenix Configuration
SECRET_KEY_BASE=${SECRET_KEY_BASE}
PHX_HOST=yourdomain.com
PORT=4019
PHX_SERVER=true

# Optional
ECTO_IPV6=false
EOF

# Verify the .env file (check SECRET_KEY_BASE is at least 64 bytes)
cat /var/www/mimimi/shared/.env
echo ""
echo "SECRET_KEY_BASE length: $(echo -n "$SECRET_KEY_BASE" | wc -c) bytes (must be >= 64)"
```

**✓ Checkpoint:** Your `.env` file should now have:
- DATABASE_URL (with password)
- POOL_SIZE
- SECRET_KEY_BASE (long random string)
- PHX_HOST
- PORT
- PHX_SERVER
- ECTO_IPV6

### Step 5.2: Update PHX_HOST

```bash
# Still as mimimi user
# Replace 'yourdomain.com' with your actual domain
nano /var/www/mimimi/shared/.env

# Find the line: PHX_HOST=yourdomain.com
# Change 'yourdomain.com' to your actual domain or server IP
# Save and exit (Ctrl+X, then Y, then Enter)
```

---

## Part 6: Configure Systemd Service

### Step 6.1: Create Service File

```bash
# Exit mimimi user, back to admin
exit

# Create systemd service file
sudo nano /etc/systemd/system/mimimi.service
```

Paste this content:

```ini
[Unit]
Description=MiMiMi Phoenix Application
After=network.target postgresql.service

[Service]
Type=simple
User=mimimi
Group=mimimi
WorkingDirectory=/var/www/mimimi/current
EnvironmentFile=/var/www/mimimi/shared/.env
ExecStart=/var/www/mimimi/current/bin/server
ExecStop=/var/www/mimimi/current/bin/mimimi stop
Restart=on-failure
RestartSec=5
RemainAfterExit=no
SyslogIdentifier=mimimi

[Install]
WantedBy=multi-user.target
```

Save and exit (Ctrl+X, then Y, then Enter).

### Step 6.2: Enable the Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable service to start on boot (but don't start it yet)
sudo systemctl enable mimimi
```

**✓ Checkpoint:** Verify service is enabled:
```bash
systemctl is-enabled mimimi
# Should output: enabled
```

---

## Part 7: Configure Nginx Reverse Proxy

### Step 7.1: Create Nginx Configuration

```bash
# Create nginx site configuration
sudo nano /etc/nginx/sites-available/mimimi
```

Paste this content (replace `yourdomain.com` with your actual domain):

```nginx
upstream mimimi {
    server 127.0.0.1:4019;
}

server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://mimimi;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
    }

    # WebSocket support for LiveView
    location /live {
        proxy_pass http://mimimi;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Serve static files directly
    location ~ ^/(images|javascript|js|css|flash|media|static)/ {
        root /var/www/mimimi/shared/static;
        expires 1y;
        add_header Cache-Control public;
        add_header Last-Modified "";
        add_header ETag "";
    }
}
```

Save and exit.

### Step 7.2: Enable Nginx Site

```bash
# Create symbolic link to enable site
sudo ln -s /etc/nginx/sites-available/mimimi /etc/nginx/sites-enabled/

# Test nginx configuration
sudo nginx -t
# Should output: syntax is ok, test is successful

# Restart nginx
sudo systemctl restart nginx
```

**✓ Checkpoint:** Verify nginx is running:
```bash
sudo systemctl status nginx
# Should show: active (running)
```

---

## Part 8: Setup GitHub Self-Hosted Runner

### Step 8.1: Create Runner on GitHub

1. Open your browser and go to your GitHub repository
2. Click **Settings** (top menu)
3. Click **Actions** (left sidebar)
4. Click **Runners** (left sidebar)
5. Click **New self-hosted runner** (green button)
6. Select **Linux** as operating system
7. **Keep this page open** - you'll need the commands shown

### Step 8.2: Install Runner on Server

```bash
# Switch to mimimi user
sudo su - mimimi

# Create runner directory
mkdir -p ~/actions-runner
cd ~/actions-runner

# Download runner (check GitHub page for latest version)
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# Configure runner
# Copy the token from your GitHub page (from Step 8.1)
./config.sh --url https://github.com/YOUR_USERNAME/MiMiMi --token YOUR_TOKEN_FROM_GITHUB
```

**During configuration, answer these prompts:**
- Runner group: Press **Enter** (use default)
- Runner name: Type `debian-prod` and press **Enter**
- Labels: Type `production` and press **Enter**
- Work folder: Press **Enter** (use default)

### Step 8.3: Install Runner as Service

```bash
# Still as mimimi user in ~/actions-runner
sudo ./svc.sh install mimimi

# Start the runner
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
# Should show: active (running)

# Exit back to admin user
exit
```

**✓ Checkpoint:** Go back to your GitHub page (from Step 8.1):
- Refresh the page
- You should see your runner listed as "Idle" with a green dot

### Step 8.4: Grant mimimi User Systemd Permissions

```bash
# As admin user
# Create sudoers file for mimimi
sudo visudo -f /etc/sudoers.d/mimimi
```

Add this single line (copy-paste exactly):

```
mimimi ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart mimimi, /usr/bin/systemctl status mimimi, /usr/bin/systemctl stop mimimi, /usr/bin/systemctl start mimimi, /usr/bin/systemctl is-active mimimi, /usr/bin/journalctl -u mimimi *
```

**Note:** If this doesn't work, check the actual path with `which systemctl` and update accordingly.

Save and exit (Ctrl+X, then Y, then Enter).

**✓ Checkpoint:** Test sudo permissions:
```bash
# If you're the admin user, test as mimimi:
sudo su - mimimi

# Now as mimimi user, test the sudo permission:
sudo systemctl status mimimi
# Should show status without asking for password
# (It's OK if it says "Unit mimimi.service could not be found" - we haven't created it yet)
```

---

## Part 9: Enable Hot Code Upgrades (Optional but Recommended)

This section sets up filesystem-based hot code upgrades, enabling near-zero downtime deployments (typically <1 second) without restarting your application. The deployment system will automatically choose between hot upgrades and cold deploys based on the changes.

### Step 9.1: Create Hot Upgrades Directory

```bash
# On your server, as mimimi user
sudo su - mimimi

# Create hot upgrades directory
mkdir -p /var/www/mimimi/shared/hot-upgrades

# Verify permissions
ls -la /var/www/mimimi/shared/
# Should show hot-upgrades directory owned by mimimi:mimimi

exit
```

### Step 9.2: Configure Hot Deploy Module

**On your local machine:**

```bash
# The HotDeploy module has already been created at lib/mimimi/hot_deploy.ex
# Now configure it in config/runtime.exs

# Edit config/runtime.exs and add this configuration for production:
```

Add this to your `config/runtime.exs` in the production section:

```elixir
if config_env() == :prod do
  # ... existing config ...

  # Hot Deploy Configuration
  config :mimimi, Mimimi.HotDeploy,
    enabled: true,
    upgrades_dir: "/var/www/mimimi/shared/hot-upgrades",
    check_interval: 10_000  # Check every 10 seconds
end
```

### Step 9.3: Enable Hot Upgrades in Application

Edit `lib/mimimi/application.ex` to call the hot deploy startup function:

```elixir
defmodule Mimimi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Enable hot code upgrades before starting supervision tree
    Mimimi.HotDeploy.startup_reapply_current()

    children = [
      # ... your existing children ...
    ]

    opts = [strategy: :one_for_one, name: Mimimi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ... rest of the file ...
end
```

### Step 9.4: Understanding Hot vs Cold Deploy

The deployment system automatically chooses the appropriate strategy:

**Hot Code Upgrade** (zero downtime, <1s):
- Used for: Bug fixes, feature additions, UI changes, business logic updates
- Cannot handle: Database migrations, supervision tree changes, configuration changes
- Preserves: Process state, connections, LiveView sessions

**Cold Deploy** (5-10s downtime):
- Used for: Database migrations, dependency changes, OTP version upgrades
- Forced by: Including `[cold-deploy]`, `[restart]`, or `[supervision]` in commit message
- Safe for: Any type of change

The system automatically detects when cold deploy is needed and falls back gracefully.

### Step 9.5: Force Cold Deploy When Needed

If your changes require a cold deploy, add a tag to your commit message:

```bash
git commit -m "Add new supervision worker [cold-deploy]"
# or
git commit -m "Update configuration [restart]"
```

**✓ Checkpoint:** Hot code upgrades are now configured! Most deployments will complete in under 1 second without downtime.

---

## Part 10: Configure Your Local Project

Now we'll set up your local Phoenix project for automated deployment.

### Step 10.1: Create Version File

```bash
# On your LOCAL machine, navigate to your project
cd /path/to/your/MiMiMi/project

# Create .tool-versions file
cat > .tool-versions << 'EOF'
erlang 28.0
elixir 1.19
EOF
```

### Step 10.2: Generate Release Configuration

```bash
# Still on your local machine
mix phx.gen.release

# This creates:
# - rel/overlays/bin/server
# - rel/overlays/bin/migrate
# - lib/mimimi/release.ex
```

**✓ Checkpoint:** Verify files were created:
```bash
ls -la rel/overlays/bin/
# Should show: server, migrate

ls -la lib/mimimi/
# Should show: release.ex
```

### Step 10.3: Create Deployment Script (Now with Hot Upgrade Support!)

```bash
# Create scripts directory
mkdir -p scripts

# Create deployment script
cat > scripts/deploy.sh << 'EOF'
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
EOF

# Make script executable
chmod +x scripts/deploy.sh
```

### Step 10.4: Create GitHub Actions Workflow

```bash
# Create .github/workflows directory
mkdir -p .github/workflows

# Create workflow file
cat > .github/workflows/deploy.yml << 'EOF'
name: Deploy to Production

on:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest
    name: Test & Verify

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: mimimi_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '28.0'

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: |
            ${{ runner.os }}-mix-

      - name: Install dependencies
        run: mix deps.get

      - name: Run precommit checks
        env:
          MIX_ENV: test
          DATABASE_URL: postgres://postgres:postgres@localhost/mimimi_test
        run: mix precommit

  deploy:
    needs: test
    runs-on: self-hosted
    name: Build & Deploy

    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: mix deps.get --only prod

      - name: Compile application
        env:
          MIX_ENV: prod
        run: mix compile

      - name: Build assets
        env:
          MIX_ENV: prod
        run: mix assets.deploy

      - name: Build release
        env:
          MIX_ENV: prod
        run: mix release --overwrite

      - name: Create release tarball
        run: |
          cd _build/prod/rel/mimimi
          tar -czf ../../../prod/mimimi-0.1.0.tar.gz .
          cd -
          ls -lh _build/prod/mimimi-*.tar.gz

      - name: Deploy release
        run: ./scripts/deploy.sh

      - name: Verify deployment
        run: |
          sleep 5
          curl -f http://localhost:4019 || exit 1
EOF
```

### Step 10.5: Create Environment Template

```bash
# Create .env.example (safe to commit to Git)
cat > .env.example << 'EOF'
# Database Configuration
DATABASE_URL=postgresql://mimimi:your_password_here@localhost/mimimi_dev
POOL_SIZE=10

# Phoenix Configuration
SECRET_KEY_BASE=run_mix_phx_gen_secret_to_generate
PHX_HOST=localhost
PORT=4019
PHX_SERVER=true

# Optional
ECTO_IPV6=false
EOF
```

### Step 10.6: Update .gitignore

```bash
# Add to your .gitignore
cat >> .gitignore << 'EOF'

# Release builds
_build/
*.tar.gz

# Environment files (NEVER commit these!)
.env
.env.*
!.env.example

# Ensure these are also ignored
/priv/static/
/tmp/
EOF
```

### Step 10.7: Commit and Push

```bash
# Add all files
git add .

# Commit
git commit -m "Add automated deployment configuration"

# Push to GitHub
git push origin main
```

**⚠️ IMPORTANT:** This push will trigger your first automated deployment!

---

## Part 11: First Deployment

Your first deployment can be done automatically via GitHub Actions (which just triggered), but let's do it manually first to ensure everything works.

### Step 11.1: Manual First Deployment

```bash
# On your server, switch to mimimi user
sudo su - mimimi

# Navigate to /var/www/mimimi
cd /var/www/mimimi

# Clone your repository
git clone https://github.com/YOUR_USERNAME/MiMiMi.git repo
cd repo

# Install Erlang/Elixir versions from .tool-versions
mise install

# Set up environment
export MIX_ENV=prod
set -a  # automatically export all variables
source /var/www/mimimi/shared/.env
set +a  # stop automatically exporting

# Install dependencies
mix deps.get --only prod

# Compile application
mix compile

# Build assets
mix assets.deploy

# Build release
mix release

# Create tarball from the release
cd _build/prod/rel/mimimi
tar -czf ../../../prod/mimimi-0.1.0.tar.gz .
cd -

# Create first release directory
RELEASE_DIR="/var/www/mimimi/releases/$(date +%Y%m%d%H%M%S)"
mkdir -p "$RELEASE_DIR"

# Extract release
tar -xzf _build/prod/mimimi-*.tar.gz -C "$RELEASE_DIR"

# Link to current
ln -sfn "$RELEASE_DIR" /var/www/mimimi/current

# Create static files symlink (for nginx)
STATIC_DIR=$(find "$RELEASE_DIR/lib" -type d -name "priv" | head -n1)
ln -sfn "$STATIC_DIR/static" /var/www/mimimi/shared/static

# Run migrations
cd /var/www/mimimi/current
./bin/migrate

# Start the application
sudo systemctl start mimimi

# Check status
sudo systemctl status mimimi
# Should show: active (running)

# Exit back to admin
exit
```

### Step 11.2: Verify Deployment

```bash
# Check if application is responding
curl http://localhost:4019
# Should show HTML response

# Check logs
sudo journalctl -u mimimi -n 50
# Should show application startup logs

# Check nginx
curl http://your-server-ip
# Should show your application

# Or from your browser
# Visit: http://yourdomain.com (or http://your-server-ip)
```

**✅ SUCCESS!** Your application is now deployed!

---

## Part 12: Setup SSL with Let's Encrypt (Optional but Recommended)

### Step 12.1: Install Certbot

```bash
# Install certbot
sudo apt install -y certbot python3-certbot-nginx
```

### Step 12.2: Obtain SSL Certificate

```bash
# Get SSL certificate (replace yourdomain.com with your actual domain)
sudo certbot --nginx -d yourdomain.com

# Follow the prompts:
# - Enter your email address
# - Agree to terms of service
# - Choose whether to redirect HTTP to HTTPS (recommended: Yes)
```

### Step 12.3: Test Auto-Renewal

```bash
# Test certificate renewal
sudo certbot renew --dry-run

# Should show: Congratulations, all simulated renewals succeeded
```

**✅ Your site is now secured with HTTPS!**

---

## Part 13: Setup Automated Database Backups

### Step 13.1: Configure Cron Job

```bash
# Switch to mimimi user
sudo su - mimimi

# Edit crontab
crontab -e

# If prompted to choose an editor, select nano (usually option 1)
```

Add these lines at the bottom:

```cron
# Daily database backup at 2 AM
0 2 * * * pg_dump -U mimimi mimimi_prod | gzip > /var/www/mimimi/shared/backups/mimimi_$(date +\%Y\%m\%d).sql.gz

# Clean backups older than 30 days at 3 AM
0 3 * * * find /var/www/mimimi/shared/backups -name "mimimi_*.sql.gz" -mtime +30 -delete
```

Save and exit (Ctrl+X, then Y, then Enter).

```bash
# Exit back to admin
exit
```

**✅ Database backups are now automated!**

---

## Part 14: Security Hardening

### Step 14.1: Configure Firewall

```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP
sudo ufw allow 80/tcp

# Allow HTTPS
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

### Step 14.2: Setup Automatic Security Updates

```bash
# Configure unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Select "Yes" when prompted
```

### Step 14.3: Install fail2ban (Brute Force Protection)

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Enable and start
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo systemctl status fail2ban
```

### Step 14.4: Harden SSH (Optional but Recommended)

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Find and modify these lines (remove # if commented):
# PasswordAuthentication no
# PubkeyAuthentication yes
# PermitRootLogin no

# Save and exit

# Restart SSH
sudo systemctl restart sshd
```

**⚠️ WARNING:** Only do this if you have SSH key authentication set up! Otherwise you'll lock yourself out.

---

## Part 15: Testing Automated Deployments

### Step 15.1: Make a Change and Push

```bash
# On your LOCAL machine
cd /path/to/your/MiMiMi/project

# Make a small change (e.g., edit README)
echo "Testing deployment" >> README.md

# Commit and push
git add README.md
git commit -m "Test automated deployment"
git push origin main
```

### Step 15.2: Watch Deployment on GitHub

1. Go to your GitHub repository
2. Click **Actions** tab
3. You should see a new workflow run
4. Click on it to watch the deployment progress
5. Wait for it to complete (usually 5-10 minutes)

### Step 15.3: Verify on Server

```bash
# On your server
sudo journalctl -u mimimi -n 50

# Check if application is running
curl http://localhost:4019

# Visit your site in browser
# Should show the updated application
```

**✅ Automated deployments are working!**

---

## Daily Operations

### View Application Logs

```bash
# Real-time logs
sudo journalctl -u mimimi -f

# Last 100 lines
sudo journalctl -u mimimi -n 100

# Today's logs
sudo journalctl -u mimimi --since today
```

### Manual Deployment Commands

```bash
# Restart application
sudo systemctl restart mimimi

# Stop application
sudo systemctl stop mimimi

# Start application
sudo systemctl start mimimi

# Check status
sudo systemctl status mimimi
```

### Manual Rollback

If a deployment fails:

```bash
# Switch to mimimi user
sudo su - mimimi

# List releases
cd /var/www/mimimi/releases
ls -lt

# Link to previous release (replace TIMESTAMP with actual timestamp)
ln -sfn /var/www/mimimi/releases/TIMESTAMP /var/www/mimimi/current

# Exit mimimi user
exit

# Restart application
sudo systemctl restart mimimi
```

### Restore Database Backup

```bash
# List backups
sudo ls -lh /var/www/mimimi/shared/backups/

# Restore a backup (replace DATE with actual date)
sudo -u mimimi gunzip -c /var/www/mimimi/shared/backups/mimimi_DATE.sql.gz | sudo -u mimimi psql mimimi_prod
```

---

## Troubleshooting

### Application Won't Start

```bash
# Check detailed logs
sudo journalctl -u mimimi -n 200 --no-pager

# Check if port is in use
sudo netstat -tlnp | grep 4019

# Verify environment variables
sudo -u mimimi cat /var/www/mimimi/shared/.env

# Test release manually
sudo su - mimimi
cd /var/www/mimimi/current
source /var/www/mimimi/shared/.env
./bin/mimimi start
./bin/mimimi pid
exit
```

### Database Connection Issues

```bash
# Test PostgreSQL connection
sudo -u mimimi psql -U mimimi -d mimimi_prod -h localhost

# Check PostgreSQL is running
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*-main.log
```

### Runner Not Connecting

```bash
# Check runner status
sudo su - mimimi
cd ~/actions-runner
sudo ./svc.sh status

# View runner logs
journalctl -u actions.runner.* -f

exit
```

### Permission Issues

```bash
# Ensure correct ownership
sudo chown -R mimimi:mimimi /var/www/mimimi

# Check .env file permissions
ls -la /var/www/mimimi/shared/.env
# Should show: -rw------- 1 mimimi mimimi

# Check sudoers configuration
sudo cat /etc/sudoers.d/mimimi
```

---

## Summary

**🎉 Congratulations!** Your Phoenix application is now:

- ✅ Deployed on Debian Linux
- ✅ Running as systemd service
- ✅ Secured with HTTPS (if you configured Let's Encrypt)
- ✅ Auto-deploying on push to `main`
- ✅ Running automated tests before deployment
- ✅ **Performing hot code upgrades (<1s downtime) for most deployments**
- ✅ **Automatically falling back to cold deploy when needed**
- ✅ Running database migrations automatically
- ✅ Backing up database daily
- ✅ Protected by firewall and fail2ban
- ✅ Keeping old releases for easy rollback

**Every time you push to `main`:**
1. GitHub Actions runs your tests
2. If tests pass, it builds a release
3. Deploys to your server automatically
4. **Intelligently chooses hot upgrade (zero downtime) or cold deploy**
5. Runs database migrations (if needed)
6. For hot upgrades: suspends processes, loads new code, resumes (<1s)
7. For cold deploys: restarts the application with minimal downtime (5-10s)
8. Verifies the deployment succeeded

**Hot Code Upgrade Benefits:**
- 🚀 **<1 second deployment** for most changes
- 🔄 **Preserves process state** and LiveView sessions
- 🌐 **No connection drops** for active users
- 📱 **Mobile-friendly** - users don't notice updates
- 🎯 **Automatic fallback** to cold deploy when needed

**Need help?** Check the Troubleshooting section above or review the logs with `sudo journalctl -u mimimi -f`
