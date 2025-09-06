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
        
        # Update .env file with new keys
        if [ -f ".env" ]; then
            sed -i "/^XRAY_REALITY_PRIVKEY=/d" .env
            sed -i "/^XRAY_REALITY_PUBKEY=/d" .env
            echo "XRAY_REALITY_PRIVKEY=$XRAY_REALITY_PRIVKEY" >> .env
            echo "XRAY_REALITY_PUBKEY=$XRAY_REALITY_PUBKEY" >> .env
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
            echo "XRAY_REALITY_SHORT_IDS=\"$XRAY_REALITY_SHORT_IDS\"" >> .env
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
    
    # Create Xray config directory
    mkdir -p /usr/local/etc/xray
    
    # Create empty config file
    cat > /usr/local/etc/xray/config.json <<EOL
{
  "log": {
    "loglevel": "warning"
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
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/yourdomain.com/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/yourdomain.com/privkey.pem"
            }
          ]
        },
        "wsSettings": {
          "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOL
    
    # Set permissions
    chown -R nobody:nogroup /usr/local/etc/xray
    
    # Enable and start Xray
    systemctl enable xray
    systemctl start xray
    
    echo -e "${GREEN}Xray installed and started.${NC}"
else
    echo -e "${YELLOW}Xray is already installed.${NC}"
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

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Please complete the following steps:${NC}"
echo "1. Edit the .env file with your configuration"
echo "2. Start the bot with: systemctl start xray-bot"
echo "3. Check logs with: journalctl -u xray-bot -f"
echo -e "\n${GREEN}For SSL certificate setup, run:${NC}"
echo "certbot certonly --nginx -d yourdomain.com"
