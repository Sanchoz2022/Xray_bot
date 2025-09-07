#!/bin/bash

# Quick Server Status Check Script
# This script checks if the server is properly configured and accessible

echo "=== Quick Server Status Check ==="
echo "Timestamp: $(date)"
echo

SERVER_IP="194.87.30.246"

echo "1. Testing server connectivity..."
ping -c 3 "$SERVER_IP" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Server $SERVER_IP is reachable"
else
    echo "✗ Server $SERVER_IP is not reachable"
    exit 1
fi

echo
echo "2. Testing port 443 connectivity..."
timeout 5 nc -z "$SERVER_IP" 443 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Port 443 is open on $SERVER_IP"
else
    echo "✗ Port 443 is closed or filtered on $SERVER_IP"
fi

echo
echo "3. Testing HTTPS response..."
timeout 10 curl -k -I "https://$SERVER_IP" 2>/dev/null | head -1
CURL_RESULT=$?
if [ $CURL_RESULT -eq 0 ]; then
    echo "✓ HTTPS service responds"
else
    echo "✗ HTTPS service does not respond (this may be normal for Reality)"
fi

echo
echo "4. Testing with openssl..."
timeout 10 openssl s_client -connect "$SERVER_IP:443" -servername www.google.com < /dev/null 2>/dev/null | grep -q "CONNECTED"
if [ $? -eq 0 ]; then
    echo "✓ SSL/TLS connection successful"
else
    echo "✗ SSL/TLS connection failed"
fi

echo
echo "=== Server Commands to Run ==="
echo "If port 443 is closed, run on server:"
echo "  sudo bash fix_xray_binding.sh"
echo "  sudo systemctl status xray"
echo "  sudo netstat -tlnp | grep :443"
echo
echo "If still not working, check server logs:"
echo "  sudo journalctl -u xray -f"
