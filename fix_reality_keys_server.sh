#!/bin/bash

# Fix Reality Keys Server Script
# This script synchronizes Reality keys between server config and bot .env

echo "=== Fixing Reality Keys on Server ==="
echo "Timestamp: $(date)"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗${NC} Please run as root (use sudo)"
    exit 1
fi

echo "1. Stopping services..."
systemctl stop xray
systemctl stop xray-bot
print_status $? "Services stopped"

echo
echo "2. Reading Reality keys from server config..."
SERVER_CONFIG="/usr/local/etc/xray/config.json"
BOT_ENV="/root/Xray_bot/.env"

if [ ! -f "$SERVER_CONFIG" ]; then
    echo -e "${RED}✗${NC} Server config not found: $SERVER_CONFIG"
    exit 1
fi

# Extract keys from server config using Python
PRIVATE_KEY=$(python3 -c "
import json
try:
    with open('$SERVER_CONFIG', 'r') as f:
        config = json.load(f)
    for inbound in config.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            reality = inbound.get('streamSettings', {}).get('realitySettings', {})
            if 'privateKey' in reality:
                print(reality['privateKey'])
                break
except Exception as e:
    print('')
")

SHORT_IDS=$(python3 -c "
import json
try:
    with open('$SERVER_CONFIG', 'r') as f:
        config = json.load(f)
    for inbound in config.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            reality = inbound.get('streamSettings', {}).get('realitySettings', {})
            if 'shortIds' in reality:
                print(json.dumps(reality['shortIds']))
                break
except Exception as e:
    print('[]')
")

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}✗${NC} Could not extract private key from server config"
    exit 1
fi

echo "Found private key: $PRIVATE_KEY"
echo "Found short IDs: $SHORT_IDS"

echo
echo "3. Generating public key..."
if [ -f "/usr/local/bin/xray" ]; then
    # Try different methods to generate public key
    PUBLIC_KEY=""
    
    # Method 1: Standard x25519 with -i flag
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | /usr/local/bin/xray x25519 -i 2>/dev/null | tail -1 | tr -d '\n\r')
    
    # Method 2: If that fails, try without -i flag
    if [ -z "$PUBLIC_KEY" ]; then
        PUBLIC_KEY=$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" 2>/dev/null | tail -1 | tr -d '\n\r')
    fi
    
    # Method 3: Try generating new keys if extraction fails
    if [ -z "$PUBLIC_KEY" ]; then
        echo "Generating new Reality keys..."
        KEY_OUTPUT=$(/usr/local/bin/xray x25519 2>/dev/null)
        PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | cut -d':' -f2 | tr -d ' \n\r')
        PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | cut -d':' -f2 | tr -d ' \n\r')
        
        if [ ! -z "$PRIVATE_KEY" ] && [ ! -z "$PUBLIC_KEY" ]; then
            echo "Generated new keys:"
            echo "  Private: $PRIVATE_KEY"
            echo "  Public: $PUBLIC_KEY"
            
            # Update server config with new private key
            python3 -c "
import json
try:
    with open('$SERVER_CONFIG', 'r') as f:
        config = json.load(f)
    
    for inbound in config.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            reality = inbound.get('streamSettings', {}).get('realitySettings', {})
            if 'privateKey' in reality:
                reality['privateKey'] = '$PRIVATE_KEY'
                break
    
    with open('$SERVER_CONFIG', 'w') as f:
        json.dump(config, f, indent=2)
    print('Updated server config with new private key')
except Exception as e:
    print(f'Failed to update server config: {e}')
"
        fi
    fi
    
    if [ ! -z "$PUBLIC_KEY" ]; then
        echo "Using public key: $PUBLIC_KEY"
    else
        echo -e "${RED}✗${NC} Failed to generate public key"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Xray binary not found"
    exit 1
fi

echo
echo "4. Updating bot .env file..."
if [ ! -f "$BOT_ENV" ]; then
    echo -e "${RED}✗${NC} Bot .env file not found: $BOT_ENV"
    exit 1
fi

# Backup original .env
cp "$BOT_ENV" "$BOT_ENV.backup.$(date +%Y%m%d_%H%M%S)"
print_status $? "Created backup of .env file"

# Update .env file
sed -i "s/^XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$PRIVATE_KEY/" "$BOT_ENV"
sed -i "s/^XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" "$BOT_ENV"
sed -i "s/^XRAY_REALITY_SHORT_IDS=.*/XRAY_REALITY_SHORT_IDS=$SHORT_IDS/" "$BOT_ENV"

print_status $? "Updated bot .env file"

echo
echo "5. Verifying updated configuration..."
echo "Bot .env Reality settings:"
grep "XRAY_REALITY" "$BOT_ENV"

echo
echo "6. Starting services..."
systemctl start xray
sleep 2
systemctl is-active --quiet xray
print_status $? "Xray service started"

systemctl start xray-bot
sleep 2
systemctl is-active --quiet xray-bot
print_status $? "Xray-bot service started"

echo
echo "7. Testing port 443..."
sleep 3
netstat -tlnp | grep :443 > /dev/null 2>&1
print_status $? "Port 443 is listening"

echo
echo "=== Fix Complete ==="
echo "Reality keys have been synchronized between server and bot."
echo "Services have been restarted."
echo
echo "Next steps:"
echo "1. Test the connection with your client"
echo "2. Check logs: journalctl -u xray -f"
echo "3. Check bot logs: journalctl -u xray-bot -f"
echo
echo "If issues persist, run the diagnostic script: ./server_diagnostic.sh"
