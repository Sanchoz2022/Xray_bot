#!/bin/bash

# Fix Xray Binding Script
# This script fixes Xray to listen on the correct IP address

echo "=== Fixing Xray IP Binding ==="
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗${NC} Please run as root (use sudo)"
    exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"
SERVER_IP="194.87.30.246"

echo "1. Stopping Xray service..."
systemctl stop xray
print_status $? "Xray service stopped"

echo
echo "2. Backing up current configuration..."
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
print_status $? "Configuration backed up"

echo
echo "3. Updating Xray configuration to listen on $SERVER_IP:443..."

# Update the configuration to listen on specific IP
python3 -c "
import json

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    # Find and update the VLESS inbound
    for inbound in config.get('inbounds', []):
        if inbound.get('protocol') == 'vless' and inbound.get('port') == 443:
            inbound['listen'] = '$SERVER_IP'
            print(f'Updated VLESS inbound to listen on $SERVER_IP:443')
            break
    
    # Save updated config
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    
    print('Configuration updated successfully')
    
except Exception as e:
    print(f'Error updating configuration: {e}')
    exit(1)
"

UPDATE_RESULT=$?
print_status $UPDATE_RESULT "Configuration updated"

if [ $UPDATE_RESULT -ne 0 ]; then
    echo "Restoring backup..."
    cp "$CONFIG_FILE.backup."* "$CONFIG_FILE" 2>/dev/null
    exit 1
fi

echo
echo "4. Testing updated configuration..."
/usr/local/bin/xray -test -config "$CONFIG_FILE"
CONFIG_TEST_RESULT=$?
print_status $CONFIG_TEST_RESULT "Configuration test passed"

if [ $CONFIG_TEST_RESULT -ne 0 ]; then
    echo "Configuration test failed. Restoring backup..."
    cp "$CONFIG_FILE.backup."* "$CONFIG_FILE" 2>/dev/null
    exit 1
fi

echo
echo "5. Starting Xray service..."
systemctl start xray
sleep 3

systemctl is-active --quiet xray
print_status $? "Xray service started"

echo
echo "6. Checking port binding..."
netstat -tlnp | grep "$SERVER_IP:443" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Xray is listening on $SERVER_IP:443"
    netstat -tlnp | grep "$SERVER_IP:443"
else
    echo -e "${RED}✗${NC} Xray is not listening on $SERVER_IP:443"
    echo "Current port bindings:"
    netstat -tlnp | grep :443
fi

echo
echo "7. Testing external connectivity..."
timeout 5 nc -z "$SERVER_IP" 443 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Port 443 is accessible from external interface"
else
    echo -e "${YELLOW}⚠${NC} Port 443 may not be accessible externally (this is normal for some network configurations)"
fi

echo
echo "=== Binding Fix Complete ==="
echo "Xray should now be listening on $SERVER_IP:443"
echo "Test your client connection now."
echo
echo "If issues persist:"
echo "1. Check firewall: sudo ufw status"
echo "2. Check logs: journalctl -u xray -f"
echo "3. Verify client configuration matches server Reality keys"
