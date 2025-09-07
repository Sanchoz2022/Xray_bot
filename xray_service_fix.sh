#!/bin/bash

# Xray Service Fix Script
# This script diagnoses and fixes Xray service startup issues

echo "=== Xray Service Fix Script ==="
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

echo "1. Checking Xray service status..."
systemctl stop xray 2>/dev/null
systemctl stop xray-bot 2>/dev/null

echo
echo "2. Checking Xray configuration..."
CONFIG_FILE="/usr/local/etc/xray/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗${NC} Xray config file not found: $CONFIG_FILE"
    exit 1
fi

# Validate JSON
python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1
print_status $? "Xray config is valid JSON"

echo
echo "3. Testing Xray configuration..."
/usr/local/bin/xray -test -config "$CONFIG_FILE"
CONFIG_TEST_RESULT=$?
print_status $CONFIG_TEST_RESULT "Xray configuration test"

if [ $CONFIG_TEST_RESULT -ne 0 ]; then
    echo -e "${RED}Configuration test failed. Checking common issues...${NC}"
    
    # Check for missing log directories
    echo "Creating log directories..."
    mkdir -p /var/log/xray
    chown nobody:nogroup /var/log/xray
    chmod 755 /var/log/xray
    print_status $? "Created log directories"
    
    # Test again
    echo "Re-testing configuration..."
    /usr/local/bin/xray -test -config "$CONFIG_FILE"
    CONFIG_TEST_RESULT=$?
    print_status $CONFIG_TEST_RESULT "Xray configuration re-test"
fi

echo
echo "4. Checking file permissions..."
chown nobody:nogroup "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
print_status $? "Set config file permissions"

echo
echo "5. Checking systemd service file..."
SERVICE_FILE="/etc/systemd/system/xray.service"

if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating Xray systemd service file..."
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    print_status $? "Created systemd service file"
    
    systemctl daemon-reload
    print_status $? "Reloaded systemd daemon"
    
    systemctl enable xray
    print_status $? "Enabled Xray service"
else
    print_status 0 "Systemd service file exists"
fi

echo
echo "6. Starting Xray service..."
systemctl start xray
sleep 3

systemctl is-active --quiet xray
XRAY_ACTIVE=$?
print_status $XRAY_ACTIVE "Xray service is active"

if [ $XRAY_ACTIVE -ne 0 ]; then
    echo "Checking Xray service logs..."
    journalctl -u xray --no-pager -n 20
    
    echo
    echo "Trying to start Xray manually for debugging..."
    timeout 10 /usr/local/bin/xray run -config "$CONFIG_FILE" &
    MANUAL_PID=$!
    sleep 5
    
    if kill -0 $MANUAL_PID 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Xray starts manually"
        kill $MANUAL_PID 2>/dev/null
    else
        echo -e "${RED}✗${NC} Xray fails to start manually"
    fi
fi

echo
echo "7. Checking ports..."
sleep 2
netstat -tlnp | grep :443 > /dev/null 2>&1
print_status $? "Port 443 is listening"

netstat -tlnp | grep :50051 > /dev/null 2>&1
print_status $? "Port 50051 is listening"

echo
echo "8. Starting bot service..."
systemctl start xray-bot
sleep 2

systemctl is-active --quiet xray-bot
print_status $? "Xray-bot service is active"

echo
echo "=== Service Status Summary ==="
echo "Xray service:"
systemctl status xray --no-pager -l

echo
echo "Xray-bot service:"
systemctl status xray-bot --no-pager -l

echo
echo "=== Port Status ==="
netstat -tlnp | grep -E ':(443|50051)'

echo
echo "=== Next Steps ==="
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✓${NC} Xray service is running successfully"
    echo "You can now test the connection with your client"
else
    echo -e "${RED}✗${NC} Xray service failed to start"
    echo "Check logs with: journalctl -u xray -f"
    echo "Check config with: /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json"
fi
