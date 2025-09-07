#!/bin/bash

# Simple Reality fix script
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    log_error "Run as root: sudo $0"
    exit 1
fi

log_info "Fixing Reality configuration..."

# Stop services
systemctl stop xray || true
systemctl stop xray-bot || true

# Generate new short ID
NEW_SHORT_ID=$(openssl rand -hex 8)
log_info "New short ID: $NEW_SHORT_ID"

# Get current private key
PRIVATE_KEY=""
if [ -f ".env" ]; then
    PRIVATE_KEY=$(grep "XRAY_REALITY_PRIVKEY=" .env | cut -d= -f2 | tr -d '"' | tr -d "'")
fi

if [ -z "$PRIVATE_KEY" ]; then
    log_error "Private key not found in .env file"
    exit 1
fi

# Backup and update config
cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup

# Update only the problematic parts
log_info "Updating short IDs..."
sed -i 's/"shortIds": \[.*\]/"shortIds": ["", "'$NEW_SHORT_ID'"]/' /usr/local/etc/xray/config.json

# Add IPv6 support
log_info "Adding IPv6 support..."
sed -i 's/"port": 443,/"listen": "::",\n            "port": 443,/' /usr/local/etc/xray/config.json

# Test configuration
log_info "Testing configuration..."
if xray -test -config /usr/local/etc/xray/config.json; then
    log_success "Configuration is valid"
else
    log_error "Configuration test failed, restoring backup"
    mv /usr/local/etc/xray/config.json.backup /usr/local/etc/xray/config.json
    exit 1
fi

# Update .env file
if [ -f ".env" ]; then
    if grep -q "XRAY_REALITY_SHORT_IDS=" .env; then
        sed -i "s/XRAY_REALITY_SHORT_IDS=.*/XRAY_REALITY_SHORT_IDS='[\"\", \"$NEW_SHORT_ID\"]'/" .env
    else
        echo "XRAY_REALITY_SHORT_IDS='[\"\", \"$NEW_SHORT_ID\"]'" >> .env
    fi
    log_success ".env updated"
fi

# Start services
log_info "Starting services..."
systemctl start xray
sleep 3

if systemctl is-active --quiet xray; then
    log_success "Xray started successfully"
else
    log_error "Failed to start Xray"
    journalctl -u xray --no-pager -n 5
    exit 1
fi

# Start bot if configured
if [ -f ".env" ] && ! grep -q "BOT_TOKEN=your_bot_token_here" .env; then
    systemctl start xray-bot || true
fi

log_success "Reality configuration fixed!"
log_info "New short ID: $NEW_SHORT_ID"
log_info "IPv6 support added"
log_info "Please regenerate VLESS keys in your bot"
