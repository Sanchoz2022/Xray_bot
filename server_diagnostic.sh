#!/bin/bash

# Server Diagnostic Script for Xray Reality Issues
# This script helps diagnose Reality verification and connection problems

echo "=== Xray Reality Server Diagnostic ==="
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

echo "1. Checking Xray service status..."
systemctl is-active --quiet xray
print_status $? "Xray service is running"

systemctl is-enabled --quiet xray
print_status $? "Xray service is enabled"

echo
echo "2. Checking port 443 status..."
netstat -tlnp | grep :443 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Port 443 is listening"
    netstat -tlnp | grep :443
else
    echo -e "${RED}✗${NC} Port 443 is not listening"
fi

echo
echo "3. Checking gRPC API port 50051..."
netstat -tlnp | grep :50051 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} gRPC API port 50051 is listening"
    netstat -tlnp | grep :50051
else
    echo -e "${RED}✗${NC} gRPC API port 50051 is not listening"
fi

echo
echo "4. Checking Xray configuration..."
if [ -f "/usr/local/etc/xray/config.json" ]; then
    echo -e "${GREEN}✓${NC} Xray config file exists"
    
    # Check if config is valid JSON
    python3 -m json.tool /usr/local/etc/xray/config.json > /dev/null 2>&1
    print_status $? "Xray config is valid JSON"
    
    # Extract Reality keys from config
    echo
    echo "Reality configuration in server config.json:"
    if command -v jq > /dev/null 2>&1; then
        PRIVATE_KEY=$(jq -r '.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.privateKey' /usr/local/etc/xray/config.json 2>/dev/null)
        SHORT_IDS=$(jq -r '.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.shortIds[]' /usr/local/etc/xray/config.json 2>/dev/null)
        
        echo "  Private Key: $PRIVATE_KEY"
        echo "  Short IDs: $SHORT_IDS"
    else
        print_warning "jq not installed, cannot parse JSON config"
    fi
else
    echo -e "${RED}✗${NC} Xray config file not found"
fi

echo
echo "5. Checking bot .env configuration..."
if [ -f "/root/Xray_bot/.env" ]; then
    echo -e "${GREEN}✓${NC} Bot .env file exists"
    
    echo "Bot Reality configuration:"
    grep "XRAY_REALITY" /root/Xray_bot/.env | while read line; do
        echo "  $line"
    done
else
    echo -e "${RED}✗${NC} Bot .env file not found at /root/Xray_bot/.env"
fi

echo
echo "6. Generating correct public key from private key..."
if [ -f "/usr/local/bin/xray" ]; then
    PRIVATE_KEY_FROM_CONFIG=$(grep -o 'gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI' /usr/local/etc/xray/config.json 2>/dev/null || echo "")
    
    if [ ! -z "$PRIVATE_KEY_FROM_CONFIG" ]; then
        echo "Generating public key for private key: $PRIVATE_KEY_FROM_CONFIG"
        echo "$PRIVATE_KEY_FROM_CONFIG" | /usr/local/bin/xray x25519 -i 2>/dev/null || echo "Failed to generate public key"
    else
        print_warning "Private key not found in config"
    fi
else
    echo -e "${RED}✗${NC} Xray binary not found at /usr/local/bin/xray"
fi

echo
echo "7. Checking firewall status..."
if command -v ufw > /dev/null 2>&1; then
    ufw status | grep -q "Status: active"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} UFW firewall is active"
        echo "UFW rules for port 443:"
        ufw status | grep 443 || echo "  No specific rules for port 443"
    else
        print_warning "UFW firewall is inactive"
    fi
else
    print_warning "UFW not installed"
fi

echo
echo "8. Testing Reality connection locally..."
if command -v curl > /dev/null 2>&1; then
    timeout 5 curl -k https://127.0.0.1:443 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Local HTTPS connection successful"
    else
        echo -e "${RED}✗${NC} Local HTTPS connection failed"
    fi
else
    print_warning "curl not available for connection test"
fi

echo
echo "=== Diagnostic Summary ==="
echo "If you see 'reality verification failed' errors:"
echo "1. Check that Reality keys match between server config and bot .env"
echo "2. Ensure shortIds are properly formatted (no empty strings)"
echo "3. Verify public key matches the private key"
echo
echo "If you see 'connection refused' errors:"
echo "1. Restart Xray service: sudo systemctl restart xray"
echo "2. Check firewall allows port 443: sudo ufw allow 443"
echo "3. Verify Xray config is valid and service starts without errors"
echo
echo "To fix Reality key mismatch:"
echo "1. Run: sudo systemctl stop xray"
echo "2. Update /root/Xray_bot/.env with correct keys from server config"
echo "3. Run: sudo systemctl restart xray-bot"
echo "4. Run: sudo systemctl start xray"
