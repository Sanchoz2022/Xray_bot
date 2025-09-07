#!/bin/bash

# Fix Reality configuration script
# This script fixes the VLESS key timeout issues by properly configuring short IDs

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root or with sudo"
    exit 1
fi

log_info "Fixing Reality configuration for VLESS key timeout issues..."

# Stop services
log_info "Stopping services..."
systemctl stop xray || true
systemctl stop xray-bot || true

# Generate new short ID
NEW_SHORT_ID=$(openssl rand -hex 8)
log_info "Generated new short ID: $NEW_SHORT_ID"

# Fix Xray configuration
if [ -f "/usr/local/etc/xray/config.json" ]; then
    log_info "Updating Xray configuration..."
    
    # Backup current config
    cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup
    
    # Create new configuration with IPv6 support and proper Reality settings
    cat > /usr/local/etc/xray/config.json << EOL
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "api": {
        "tag": "api",
        "services": ["HandlerService", "LoggerService", "StatsService"]
    },
    "stats": {},
    "policy": {
        "levels": {
            "0": {
                "statsUserUplink": true,
                "statsUserDownlink": true
            }
        },
        "system": {
            "statsInboundUplink": true,
            "statsInboundDownlink": true,
            "statsOutboundUplink": true,
            "statsOutboundDownlink": true
        }
    },
    "inbounds": [
        {
            "listen": "::",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "www.google.com:443"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.google.com:443",
                    "xver": 0,
                    "serverNames": [
                        "www.google.com",
                        "google.com"
                    ],
                    "privateKey": "PLACEHOLDER_PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "",
                        "$NEW_SHORT_ID"
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls"
                ]
            },
            "tag": "inbound-443"
        },
        {
            "port": 50051,
            "listen": "127.0.0.1",
            "protocol": "dokodemo-door",
            "settings": {
                "address": "127.0.0.1"
            },
            "tag": "api"
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            },
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "settings": {
                "response": {
                    "type": "http"
                }
            },
            "tag": "blocked"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "inboundTag": [
                    "api"
                ],
                "outboundTag": "api"
            },
            {
                "type": "field",
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOL
    
    # Get private key from .env and update config
    if [ -f ".env" ]; then
        PRIVATE_KEY=$(grep XRAY_REALITY_PRIVKEY= .env | cut -d= -f2 | tr -d '"')
        if [ -n "$PRIVATE_KEY" ]; then
            sed -i "s/PLACEHOLDER_PRIVATE_KEY/$PRIVATE_KEY/" /usr/local/etc/xray/config.json
        fi
    fi
    
    # Validate configuration
    log_info "Validating configuration..."
    VALIDATION_OUTPUT=$(xray -test -config /usr/local/etc/xray/config.json 2>&1)
    if [ $? -eq 0 ]; then
        log_success "Xray configuration updated with IPv6 support and validated"
    else
        log_error "Configuration validation failed:"
        echo "$VALIDATION_OUTPUT"
        log_info "Restoring backup..."
        mv /usr/local/etc/xray/config.json.backup /usr/local/etc/xray/config.json
        exit 1
    fi
else
    log_error "Xray configuration file not found"
    exit 1
fi

# Update .env file if it exists
if [ -f ".env" ]; then
    log_info "Updating .env file..."
    
    # Update or add XRAY_REALITY_SHORT_IDS
    if grep -q "XRAY_REALITY_SHORT_IDS=" .env; then
        sed -i "s/XRAY_REALITY_SHORT_IDS=.*/XRAY_REALITY_SHORT_IDS='[\"\", \"$NEW_SHORT_ID\"]'/" .env
    else
        echo "XRAY_REALITY_SHORT_IDS='[\"\", \"$NEW_SHORT_ID\"]'" >> .env
    fi
    
    log_success ".env file updated"
fi

# Start services
log_info "Starting services..."
systemctl start xray
sleep 5

if systemctl is-active --quiet xray; then
    log_success "Xray service started successfully"
else
    log_error "Failed to start Xray service"
    echo "Xray logs:"
    journalctl -u xray --no-pager -n 10
    exit 1
fi

# Start bot if configured
if [ -f ".env" ] && ! grep -q "BOT_TOKEN=your_bot_token_here" .env; then
    systemctl start xray-bot
    sleep 3
    
    if systemctl is-active --quiet xray-bot; then
        log_success "Bot service started successfully"
    else
        log_info "Bot service failed to start (may need configuration)"
    fi
fi

log_success "Reality configuration fixed!"
log_info "New short ID: $NEW_SHORT_ID"
log_info "Configuration now includes both empty string and actual short ID for better compatibility"
log_info "VLESS keys should now work without timeout issues"

# Test the configuration
log_info "Testing Reality connection..."
if [ -f ".env" ]; then
    SERVER_IP=$(grep "SERVER_IP=" .env | cut -d= -f2 2>/dev/null || echo "")
    if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "YOUR_SERVER_IP" ]; then
        if timeout 10 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
            log_success "Port 443 is accessible"
        else
            log_error "Port 443 is not accessible from this server"
        fi
    fi
fi

echo ""
log_success "Fix completed! Please regenerate VLESS keys in your bot to get working configurations."
