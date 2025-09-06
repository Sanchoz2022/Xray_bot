#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Xray
install_xray() {
    print_header "Installing Xray"
    
    if command_exists xray; then
        echo -e "${GREEN}Xray is already installed.${NC}"
        xray -version
        return 0
    fi
    
    echo -e "${GREEN}Installing Xray...${NC}"
    
    # Install prerequisites
    apt update
    apt install -y curl wget unzip jq
    
    # Install Xray using official script
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" -- install
    
    if ! command_exists xray; then
        echo -e "${RED}Failed to install Xray${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Xray installed successfully!${NC}"
    xray -version
}

# Function to generate gRPC Python files
generate_grpc_code() {
    print_header "Generating gRPC code"
    
    if ! command_exists protoc; then
        echo -e "${YELLOW}Installing protobuf compiler...${NC}"
        apt update
        apt install -y protobuf-compiler
    fi
    
    if ! command_exists python3 -m grpc_tools.protoc; then
        echo -e "${YELLOW}Installing gRPC tools...${NC}"
        pip install grpcio-tools
    fi
    
    echo -e "${GREEN}Generating gRPC code...${NC}"
    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. xray_api.proto
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to generate gRPC code${NC}"
        return 1
    fi
    
    echo -e "${GREEN}gRPC code generated successfully!${NC}"
}

# Function to configure Xray
configure_xray() {
    print_header "Configuring Xray"
    
    # Create necessary directories
    mkdir -p /usr/local/etc/xray
    mkdir -p /var/log/xray
    
    # Generate Reality keys if they don't exist
    if [ -z "$XRAY_REALITY_PRIVKEY" ] || [ -z "$XRAY_REALITY_PUBKEY" ]; then
        echo -e "${YELLOW}Generating Reality keys...${NC}"
        KEYS=$(/usr/local/bin/xray x25519)
        XRAY_REALITY_PRIVKEY=$(echo "$KEYS" | grep 'Private key:' | awk '{print $3}')
        XRAY_REALITY_PUBKEY=$(echo "$KEYS" | grep 'Public key:' | awk '{print $3}')
        
        # Set default short ID if not set
        if [ -z "$XRAY_REALITY_SHORT_IDS" ]; then
            XRAY_REALITY_SHORT_IDS="00000000"  # Default short ID
        fi
        
        # Update .env file with new keys and settings
        if [ -f ".env" ]; then
            # Remove existing settings if they exist
            sed -i "/^XRAY_REALITY_PRIVKEY=/d" .env
            sed -i "/^XRAY_REALITY_PUBKEY=/d" .env
            sed -i "/^XRAY_REALITY_SHORT_IDS=/d" .env
            
            # Add new settings
            echo "XRAY_REALITY_PRIVKEY=$XRAY_REALITY_PRIVKEY" >> .env
            echo "XRAY_REALITY_PUBKEY=$XRAY_REALITY_PUBKEY" >> .env
            echo "XRAY_REALITY_SHORT_IDS=$XRAY_REALITY_SHORT_IDS" >> .env
        fi
        
        echo -e "${GREEN}Generated Reality keys:${NC}"
        echo -e "Private key: ${XRAY_REALITY_PRIVKEY}"
        echo -e "Public key: ${XRAY_REALITY_PUBKEY}"
    fi
    
    # Generate short ID if not set
    if [ -z "$XRAY_REALITY_SHORT_IDS" ]; then
        XRAY_REALITY_SHORT_IDS=$(openssl rand -hex 8)
        
        # Update .env file with short ID
        if [ -f ".env" ]; then
            sed -i "/^XRAY_REALITY_SHORT_IDS=/d" .env
            echo "XRAY_REALITY_SHORT_IDS=$XRAY_REALITY_SHORT_IDS" >> .env
        fi
        
        echo -e "${GREEN}Generated short ID: $XRAY_REALITY_SHORT_IDS${NC}"
    fi
    
    # Generate Xray config
    echo -e "${GREEN}Generating Xray configuration...${NC}"
    
    # Source the environment variables
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
    fi
    
    # Create Xray config
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
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.google.com:443",
                    "xver": 0,
                    "serverNames": [
                        "www.google.com"
                    ],
                    "privateKey": "${XRAY_REALITY_PRIVKEY}",
                    "shortIds": [
                        "${XRAY_REALITY_SHORT_IDS}"
                    ]
                },
                "tcpSettings": {
                    "header": {
                        "type": "none"
                    }
                }
            },
            "tag": "inbound-reality"
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
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "inboundTag": ["api"],
                "outboundTag": "api"
            },
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "blocked"
            },
            {
                "type": "field",
                "outboundTag": "direct",
                "network": "tcp,udp"
            }
        ]
    }
}
EOL
    
    # Set proper permissions
    chown -R root:root /usr/local/etc/xray
    chmod -R 600 /usr/local/etc/xray
    chown -R root:root /var/log/xray
    chmod -R 600 /var/log/xray/*.log
    
    # Enable and start Xray service
    systemctl enable xray
    systemctl restart xray
    
    # Check if Xray is running
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}Xray is running successfully!${NC}"
    else
        echo -e "${RED}Failed to start Xray service${NC}"
        journalctl -u xray -n 50 --no-pager
        return 1
    fi
}

# Function to set up Python environment and database
setup_python_env() {
    print_header "Setting up Python environment"
    
    # Check if Python 3.8+ is installed
    if ! command_exists python3; then
        echo -e "${GREEN}Installing Python 3...${NC}"
        apt update
        apt install -y python3 python3-pip python3-venv
    fi
    
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if (( $(echo "$PYTHON_VERSION < 3.8" | bc -l) )); then
        echo -e "${YELLOW}Python 3.8 or higher is recommended. Found Python $PYTHON_VERSION${NC}"
    else
        echo -e "${GREEN}Python $PYTHON_VERSION is installed.${NC}"
    fi
    
    # Install system dependencies
    echo -e "${GREEN}Installing system dependencies...${NC}"
    apt update
    apt install -y python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev
    
    # Create and activate virtual environment
    if [ ! -d "venv" ]; then
        echo -e "${GREEN}Creating virtual environment...${NC}"
        python3 -m venv venv
    fi
    
    echo -e "${GREEN}Activating virtual environment and installing Python dependencies...${NC}"
    source venv/bin/activate
    
    # Upgrade pip and install wheel
    pip install --upgrade pip wheel setuptools
    
    # Install requirements
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        echo -e "${YELLOW}requirements.txt not found. Installing default dependencies...${NC}"
        pip install aiogram==2.25.1 sqlalchemy[asyncio] aiosqlite python-dotenv python-dateutil
    fi
    
    # Initialize database
    echo -e "${GREEN}Initializing database...${NC}"
    python3 -c "
import asyncio
from db import create_tables, init_db

async def setup_db():
    await create_tables()
    await init_db()

asyncio.run(setup_db())
"
    
    # Set proper permissions
    chmod 666 xray_bot.db 2>/dev/null || true
    
    echo -e "${GREEN}Python environment and database setup complete!${NC}"
    pip install -r requirements.txt
    
    # Install gRPC tools
    pip install grpcio grpcio-tools protobuf
}

# Main function
main() {
    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
    
    # Create .env file if it doesn't exist
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}Creating .env file...${NC}"
        if [ -f ".env.example" ]; then
            cp .env.example .env
        else
            cat > .env << EOL
# Telegram Bot Settings
BOT_TOKEN=your_bot_token_here
ADMIN_IDS=your_telegram_id_here
CHANNEL_USERNAME=your_channel_username

# Server Settings
SERVER_IP=$(curl -s ifconfig.me)
SERVER_DOMAIN=your_domain.com

# Xray Settings
XRAY_REALITY_PRIVKEY=
XRAY_REALITY_PUBKEY=
XRAY_REALITY_SHORT_IDS=
XRAY_REALITY_DEST=www.google.com:443

# gRPC API Settings
GRPC_API_HOST=127.0.0.1
GRPC_API_PORT=50051

# Database Settings
DATABASE_URL=sqlite:///./vpnbot.db

# Subscription Settings
DEFAULT_SUBSCRIPTION_DAYS=30
DEFAULT_DATA_LIMIT_GB=100
EOL
        fi
        
        echo -e "${YELLOW}Please edit the .env file with your configuration and run this script again.${NC}"
        exit 0
    fi
    
    # Source environment variables
    set -a
    source .env
    set +a
    
    # Install Xray
    install_xray
    
    # Generate gRPC code
    generate_grpc_code
    
    # Configure Xray
    configure_xray
    
    # Set up Python environment
    setup_python_env
    
    print_header "Setup completed successfully!"
    echo -e "${GREEN}The Xray VPN Bot has been set up successfully!${NC}"
    echo -e "${YELLOW}To start the bot, run:${NC}"
    echo -e "  source venv/bin/activate"
    echo -e "  python bot.py"
    echo -e "\n${YELLOW}Or run it in the background with:${NC}"
    echo -e "  nohup python bot.py > bot.log 2>&1 &"
}

# Run the main function
main "$@"

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/xray-bot.service"
if [ ! -f $SERVICE_FILE ]; then
    echo -e "\n${GREEN}Creating systemd service file...${NC}"
    cat > $SERVICE_FILE <<EOL
[Unit]
Description=Xray VPN Bot
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
Environment="PATH=$(pwd)/venv/bin"
ExecStart=$(pwd)/venv/bin/python3 bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL
    
    systemctl daemon-reload
    systemctl enable xray-bot
    
    echo -e "${GREEN}Service created. You can start it with:${NC}"
    echo -e "  systemctl start xray-bot"
    echo -e "  systemctl status xray-bot"
    echo -e "  journalctl -u xray-bot -f"
fi

# Set permissions
echo -e "\n${GREEN}Setting permissions...${NC}"
chmod +x setup.sh
chmod 600 .env

# Install Xray if not already installed
if ! command -v xray &> /dev/null; then
    echo -e "\n${GREEN}Installing Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    echo -e "${GREEN}Xray installed successfully.${NC}"
else
    echo -e "${YELLOW}Xray is already installed.${NC}"
fi

# Generate Reality keys if not exist in .env
echo -e "\n${GREEN}Configuring VLESS Reality...${NC}"

# Check if Reality keys exist in .env
if ! grep -q "XRAY_REALITY_PRIVKEY=" .env || grep -q "XRAY_REALITY_PRIVKEY=$" .env; then
    echo -e "${YELLOW}Generating Reality keys...${NC}"
    
    # Check if xray command is available
    if ! command -v xray &> /dev/null; then
        echo -e "${RED}Error: xray command not found. Please install Xray first.${NC}"
        exit 1
    fi
    
    # Generate Reality keys with error handling
    echo -e "${YELLOW}Running: xray x25519${NC}"
    REALITY_KEYS=$(xray x25519 2>&1)
    XRAY_EXIT_CODE=$?
    
    if [ $XRAY_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Error: xray x25519 command failed with exit code $XRAY_EXIT_CODE${NC}"
        echo -e "${RED}Output: $REALITY_KEYS${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Raw output from xray x25519:${NC}"
    echo "$REALITY_KEYS"
    
    # Parse keys - new xray format uses PrivateKey and Password
    PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n' | tr -d ' ')
    PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep "Password:" | awk '{print $2}' | tr -d '\r\n' | tr -d ' ')
    
    # Debug: show what we found
    echo "Debug - PrivateKey line: $(echo "$REALITY_KEYS" | grep "PrivateKey:")"
    echo "Debug - Password line: $(echo "$REALITY_KEYS" | grep "Password:")"
    
    echo -e "${YELLOW}Parsed private key: '$PRIVATE_KEY'${NC}"
    echo -e "${YELLOW}Parsed public key: '$PUBLIC_KEY'${NC}"
    
    if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
        # Update .env file with generated keys
        sed -i "s/XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$PRIVATE_KEY/" .env
        sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" .env
        echo -e "${GREEN}Reality keys generated and saved to .env${NC}"
        
        # Verify keys were saved
        echo -e "${YELLOW}Verifying keys in .env:${NC}"
        grep "XRAY_REALITY_PRIVKEY=" .env
        grep "XRAY_REALITY_PUBKEY=" .env
    else
        echo -e "${RED}Failed to parse Reality keys from xray output${NC}"
        echo -e "${RED}Expected format: 'PrivateKey: <key>' and 'Password: <key>'${NC}"
        
        # Try legacy format parsing
        echo -e "${YELLOW}Trying legacy format parsing...${NC}"
        PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep -i "private key:" | awk '{print $3}' | tr -d '\r\n')
        PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep -i "public key:" | awk '{print $3}' | tr -d '\r\n')
        
        if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ]; then
            sed -i "s/XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$PRIVATE_KEY/" .env
            sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" .env
            echo -e "${GREEN}Reality keys parsed with legacy format and saved to .env${NC}"
        else
            # Try regex parsing as last resort
            echo -e "${YELLOW}Trying regex parsing...${NC}"
            PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep -oE '[A-Za-z0-9_-]{43}' | head -1)
            PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep -oE '[A-Za-z0-9_-]{43}' | tail -1)
            
            if [ -n "$PRIVATE_KEY" ] && [ -n "$PUBLIC_KEY" ] && [ "$PRIVATE_KEY" != "$PUBLIC_KEY" ]; then
                sed -i "s/XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$PRIVATE_KEY/" .env
                sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" .env
                echo -e "${GREEN}Reality keys parsed with regex method and saved to .env${NC}"
            else
                echo -e "${RED}All parsing methods failed. Manual key generation required.${NC}"
                exit 1
            fi
        fi
    fi
else
    echo -e "${GREEN}Reality keys already configured in .env${NC}"
fi

# Get current configuration values from .env
SERVER_IP=$(grep "SERVER_IP=" .env | cut -d'=' -f2 | head -1)
REALITY_DEST=$(grep "XRAY_REALITY_DEST=" .env | cut -d'=' -f2 | head -1)
PRIVATE_KEY=$(grep "XRAY_REALITY_PRIVKEY=" .env | cut -d'=' -f2 | head -1)
SHORT_IDS=$(grep "XRAY_REALITY_SHORT_IDS=" .env | cut -d'=' -f2 | head -1)

# Set defaults if empty
[ -z "$SERVER_IP" ] && SERVER_IP="0.0.0.0"
[ -z "$REALITY_DEST" ] && REALITY_DEST="www.google.com:443"
[ -z "$SHORT_IDS" ] && SHORT_IDS="00000000"

# Create Xray config directory
mkdir -p /usr/local/etc/xray

echo -e "${GREEN}Creating Xray VLESS Reality configuration...${NC}"

# Create complete VLESS Reality configuration
cat > /usr/local/etc/xray/config.json <<EOL
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
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "$REALITY_DEST"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$REALITY_DEST",
                    "xver": 0,
                    "serverNames": [
                        "www.google.com",
                        "google.com"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "$SHORT_IDS"
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

# Validate Xray configuration
echo -e "${GREEN}Validating Xray configuration...${NC}"
if xray -test -config /usr/local/etc/xray/config.json; then
    echo -e "${GREEN}Xray configuration is valid.${NC}"
else
    echo -e "${RED}Xray configuration validation failed!${NC}"
    exit 1
fi

# Set proper permissions for Xray config
chown -R root:root /usr/local/etc/xray
chmod 755 /usr/local/etc/xray
chmod 644 /usr/local/etc/xray/config.json

# Create log directory with proper permissions
mkdir -p /var/log/xray
chown nobody:nogroup /var/log/xray
chmod 755 /var/log/xray

# Enable and start Xray service
echo -e "${GREEN}Starting Xray service...${NC}"
systemctl enable xray
systemctl daemon-reload
systemctl restart xray

# Wait for service to start
sleep 3

# Verify Xray is running
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray service is running successfully.${NC}"
else
    echo -e "${RED}Failed to start Xray service. Checking logs...${NC}"
    journalctl -u xray --no-pager -l --since="1 minute ago"
    exit 1
fi

# Check and configure Xray gRPC API
echo -e "\n${GREEN}Configuring Xray gRPC API...${NC}"

# Create log directory
mkdir -p /var/log/xray
chown nobody:nogroup /var/log/xray

# Check if Xray service is running
if ! systemctl is-active --quiet xray; then
    echo -e "${YELLOW}Starting Xray service...${NC}"
    systemctl start xray
    sleep 2
fi

# Wait for Xray to start
sleep 3

# Check if gRPC port is listening
if ! netstat -tlnp 2>/dev/null | grep -q ":50051"; then
    echo -e "${YELLOW}gRPC API port 50051 not found. Restarting Xray...${NC}"
    systemctl restart xray
    sleep 5
    
    # Check again
    if ! netstat -tlnp 2>/dev/null | grep -q ":50051"; then
        echo -e "${RED}Warning: gRPC API port 50051 is not listening.${NC}"
        echo -e "${YELLOW}This may cause issues with user management.${NC}"
    else
        echo -e "${GREEN}gRPC API is running on port 50051.${NC}"
    fi
else
    echo -e "${GREEN}gRPC API is running on port 50051.${NC}"
fi

# Test gRPC connectivity
echo -e "\n${GREEN}Testing gRPC connectivity...${NC}"
if command -v python3 &> /dev/null; then
    python3 -c "
import socket
import sys
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    result = sock.connect_ex(('127.0.0.1', 50051))
    sock.close()
    if result == 0:
        print('✓ gRPC port 50051 is accessible')
        sys.exit(0)
    else:
        print('✗ Cannot connect to gRPC port 50051')
        sys.exit(1)
except Exception as e:
    print(f'✗ gRPC connectivity test failed: {e}')
    sys.exit(1)
" && echo -e "${GREEN}gRPC connectivity test passed.${NC}" || echo -e "${RED}gRPC connectivity test failed.${NC}"
fi

# Enable UFW if not enabled
if ! ufw status | grep -q "Status: active"; then
    echo -e "\n${GREEN}Configuring firewall...${NC}"
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    echo -e "${GREEN}Firewall configured.${NC}"
fi

# Final system verification
echo -e "\n${GREEN}Running final system verification...${NC}"

# Check bot service
if systemctl is-enabled --quiet xray-bot; then
    echo -e "✓ ${GREEN}Bot service is enabled${NC}"
else
    echo -e "✗ ${RED}Bot service is not enabled${NC}"
fi

# Check Xray service
if systemctl is-active --quiet xray; then
    echo -e "✓ ${GREEN}Xray service is running${NC}"
else
    echo -e "✗ ${RED}Xray service is not running${NC}"
fi

# Check database file
if [ -f "xray_bot.db" ] || [ -f "bot.db" ]; then
    echo -e "✓ ${GREEN}Database file exists${NC}"
else
    echo -e "✓ ${YELLOW}Database will be created on first run${NC}"
fi

# Check .env file
if [ -f ".env" ]; then
    echo -e "✓ ${GREEN}.env file exists${NC}"
    
    # Check critical environment variables
    if grep -q "BOT_TOKEN=" .env && ! grep -q "BOT_TOKEN=$" .env; then
        echo -e "✓ ${GREEN}BOT_TOKEN is configured${NC}"
    else
        echo -e "✗ ${RED}BOT_TOKEN needs to be configured${NC}"
    fi
    
    if grep -q "ADMIN_IDS=" .env && ! grep -q "ADMIN_IDS=$" .env; then
        echo -e "✓ ${GREEN}ADMIN_IDS is configured${NC}"
    else
        echo -e "✗ ${RED}ADMIN_IDS needs to be configured${NC}"
    fi
else
    echo -e "✗ ${RED}.env file not found${NC}"
fi

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"

# Conditional instructions based on verification
if ! grep -q "BOT_TOKEN=" .env || grep -q "BOT_TOKEN=$" .env; then
    echo "1. ${RED}REQUIRED:${NC} Edit .env file and set your BOT_TOKEN"
fi

if ! grep -q "ADMIN_IDS=" .env || grep -q "ADMIN_IDS=$" .env; then
    echo "2. ${RED}REQUIRED:${NC} Edit .env file and set your ADMIN_IDS"
fi

echo "3. Start the bot: ${GREEN}systemctl start xray-bot${NC}"
echo "4. Check status: ${GREEN}systemctl status xray-bot${NC}"
echo "5. View logs: ${GREEN}journalctl -u xray-bot -f${NC}"

echo -e "\n${GREEN}Useful commands:${NC}"
echo "• Restart bot: systemctl restart xray-bot"
echo "• Restart Xray: systemctl restart xray"
echo "• Check gRPC: netstat -tlnp | grep 50051"
echo "• Update code: git pull && systemctl restart xray-bot"

echo -e "\n${GREEN}For SSL certificate setup:${NC}"
echo "certbot certonly --nginx -d yourdomain.com"
