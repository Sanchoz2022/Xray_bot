#!/bin/bash

# Полностью автоматический скрипт настройки Xray Bot сервера
# Включает все функции предыдущих скриптов

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Логирование
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Проверка root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)"
    fi
}

# Установка зависимостей с обработкой конфликтов
install_dependencies() {
    log "Установка зависимостей..."
    
    # Проверка и ожидание завершения других процессов apt
    while pgrep -f "apt|dpkg" > /dev/null; do
        warn "Ожидание завершения других процессов пакетного менеджера..."
        sleep 5
    done
    
    # Исправление сломанных зависимостей
    log "Исправление сломанных зависимостей..."
    apt --fix-broken install -y || true
    dpkg --configure -a || true
    
    # Обновление системы
    apt update
    
    # Установка aptitude для лучшего разрешения зависимостей
    apt install -y aptitude || true
    
    # Основные пакеты с обработкой ошибок
    local essential_packages=(
        "curl"
        "wget"
        "unzip" 
        "python3"
        "python3-pip"
        "net-tools"
        "lsof"
        "openssl"
        "ca-certificates"
        "gnupg"
        "chrony"
        "ufw"
    )
    
    for package in "${essential_packages[@]}"; do
        log "Установка $package..."
        if apt install -y --no-install-recommends "$package"; then
            log "✓ $package установлен"
        elif command -v aptitude &> /dev/null && aptitude install -y "$package"; then
            log "✓ $package установлен через aptitude"
        else
            warn "Не удалось установить $package, пропускаем..."
        fi
    done
    
    # Попытка исправить конфликты зависимостей
    if ! apt upgrade -y; then
        warn "Обнаружены конфликты зависимостей, исправляем..."
        apt -f install -y || true
        
        # Принудительная установка проблемных пакетов
        apt install -y --fix-missing libsoup2.4-1 || true
        apt install -y --fix-missing libappstream4 || true
        
        # Повторная попытка обновления
        apt upgrade -y --fix-missing || true
    fi
    
    # Установка Xray с обработкой ошибок
    if ! command -v xray &> /dev/null; then
        log "Установка Xray..."
        
        # Попытка стандартной установки
        if ! bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install; then
            warn "Стандартная установка не удалась, пробуем ручную установку..."
            install_xray_manual
        fi
    else
        log "Xray уже установлен"
    fi
}

# Ручная установка Xray
install_xray_manual() {
    log "Ручная установка Xray..."
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Определение архитектуры
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *) arch="64" ;;
    esac
    
    # Загрузка Xray
    local download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    
    if wget -O xray.zip "$download_url" && unzip -o xray.zip; then
        # Установка
        install -m 755 xray /usr/local/bin/xray
        mkdir -p /usr/local/etc/xray /var/log/xray
        
        if /usr/local/bin/xray version; then
            log "✓ Xray установлен вручную"
        else
            error "Ошибка при установке Xray"
        fi
    else
        error "Не удалось загрузить Xray"
    fi
    
    cd / && rm -rf "$temp_dir"
}

# Генерация Reality ключей
generate_reality_keys() {
    log "Генерация Reality ключей..."
    
    local reality_output
    reality_output=$(xray x25519 2>&1)
    
    # Парсинг ключей (поддержка разных форматов)
    if echo "$reality_output" | grep -q "PrivateKey:"; then
        REALITY_PRIVATE_KEY=$(echo "$reality_output" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n ')
        REALITY_PUBLIC_KEY=$(echo "$reality_output" | grep "Password:" | awk '{print $2}' | tr -d '\r\n ')
    elif echo "$reality_output" | grep -q "Private key:"; then
        REALITY_PRIVATE_KEY=$(echo "$reality_output" | grep "Private key:" | awk '{print $3}' | tr -d '\r\n ')
        REALITY_PUBLIC_KEY=$(echo "$reality_output" | grep "Public key:" | awk '{print $3}' | tr -d '\r\n ')
    else
        error "Не удалось сгенерировать Reality ключи"
    fi
    
    # Генерация shortId
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    
    log "Reality ключи сгенерированы:"
    log "Private Key: $REALITY_PRIVATE_KEY"
    log "Public Key: $REALITY_PUBLIC_KEY"
    log "Short ID: $REALITY_SHORT_ID"
}

# Создание конфигурации Xray
create_xray_config() {
    log "Создание конфигурации Xray..."
    
    mkdir -p /usr/local/etc/xray
    mkdir -p /var/log/xray
    
    cat > /usr/local/etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "info",
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
            "listen": "0.0.0.0",
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
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "",
                        "$REALITY_SHORT_ID"
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
EOF
}

# Создание systemd сервиса
create_systemd_service() {
    log "Создание systemd сервиса..."
    
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
Group=nogroup
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
}

# Настройка прав доступа
setup_permissions() {
    log "Настройка прав доступа..."
    
    # Создание пользователя nobody если не существует
    if ! id "nobody" &>/dev/null; then
        useradd -r -s /bin/false nobody
    fi
    
    # Настройка прав на файлы
    chown -R nobody:nogroup /usr/local/etc/xray/
    chown -R nobody:nogroup /var/log/xray/
    chmod 644 /usr/local/etc/xray/config.json
    chmod 755 /var/log/xray/
}

# Обновление .env файла бота
update_bot_env() {
    log "Обновление .env файла бота..."
    
    local bot_dir="/home/*/Project/CascadeProjects/windsurf-project"
    local env_file=""
    
    # Поиск .env файла
    for dir in $bot_dir; do
        if [[ -f "$dir/.env" ]]; then
            env_file="$dir/.env"
            break
        fi
    done
    
    if [[ -z "$env_file" ]]; then
        warn ".env файл не найден, создаем новый в /opt/xray-bot/"
        mkdir -p /opt/xray-bot
        env_file="/opt/xray-bot/.env"
    fi
    
    # Получение IP сервера
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")
    
    # Обновление/создание .env файла
    cat > "$env_file" << EOF
# Telegram Bot Settings
BOT_TOKEN=YOUR_BOT_TOKEN
ADMIN_IDS=YOUR_ADMIN_ID
CHANNEL_USERNAME=your_channel

# Server Settings
SERVER_IP=$SERVER_IP
SERVER_DOMAIN=www.google.com

# Xray Settings
XRAY_REALITY_DEST=www.google.com:443
XRAY_REALITY_PRIVKEY=$REALITY_PRIVATE_KEY
XRAY_REALITY_PUBKEY=$REALITY_PUBLIC_KEY
XRAY_REALITY_SHORT_IDS='["", "$REALITY_SHORT_ID"]'

# gRPC API Settings
GRPC_API_HOST=127.0.0.1
GRPC_API_PORT=50051

# Database Settings
DATABASE_URL=sqlite+aiosqlite:///xray_bot.db

# Subscription Settings
DEFAULT_SUBSCRIPTION_DAYS=30
EOF
    
    log ".env файл обновлен: $env_file"
}

# Запуск и активация сервисов
start_services() {
    log "Запуск сервисов..."
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Активация и запуск Xray
    systemctl enable xray
    systemctl start xray
    
    # Проверка статуса
    if systemctl is-active --quiet xray; then
        log "Xray сервис запущен успешно"
    else
        error "Не удалось запустить Xray сервис"
    fi
}

# Проверка портов
check_ports() {
    log "Проверка портов..."
    
    sleep 3  # Ждем запуска сервиса
    
    if netstat -tlnp | grep -q ":443 "; then
        log "✓ Порт 443 прослушивается"
    else
        warn "✗ Порт 443 не прослушивается"
    fi
    
    if netstat -tlnp | grep -q ":50051 "; then
        log "✓ Порт 50051 (gRPC API) прослушивается"
    else
        warn "✗ Порт 50051 не прослушивается"
    fi
}

# Создание скрипта диагностики
create_diagnostic_script() {
    log "Создание скрипта диагностики..."
    
    cat > /usr/local/bin/xray-diagnostic.sh << 'EOF'
#!/bin/bash
# Автоматический скрипт диагностики Xray Bot

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Диагностика Xray Bot ===${NC}"
echo

# Проверка статуса сервиса
echo -e "${BLUE}=== Статус сервиса ===${NC}"
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}[SUCCESS] ✓ Xray сервис активен${NC}"
else
    echo -e "${RED}[ERROR] ✗ Xray сервис не активен${NC}"
fi

# Проверка портов
echo -e "${BLUE}=== Проверка портов ===${NC}"
if netstat -tlnp | grep -q ":443 "; then
    echo -e "${GREEN}[SUCCESS] ✓ Порт 443 прослушивается${NC}"
    echo -e "${BLUE}[INFO] Процесс на порту 443: $(lsof -ti:443 | xargs ps -p | tail -n +2 | awk '{print $4}')${NC}"
else
    echo -e "${RED}[ERROR] ✗ Порт 443 не прослушивается${NC}"
fi

if netstat -tlnp | grep -q ":50051 "; then
    echo -e "${GREEN}[SUCCESS] ✓ Порт 50051 (gRPC API) прослушивается${NC}"
else
    echo -e "${RED}[ERROR] ✗ Порт 50051 не прослушивается${NC}"
fi

# Проверка конфигурации
echo -e "${BLUE}=== Проверка конфигурации ===${NC}"
if [[ -f /usr/local/etc/xray/config.json ]]; then
    echo -e "${GREEN}[SUCCESS] ✓ Конфигурационный файл существует${NC}"
    if xray test -config /usr/local/etc/xray/config.json &>/dev/null; then
        echo -e "${GREEN}[SUCCESS] ✓ Конфигурация валидна${NC}"
    else
        echo -e "${RED}[ERROR] ✗ Конфигурация содержит ошибки${NC}"
    fi
else
    echo -e "${RED}[ERROR] ✗ Конфигурационный файл не найден${NC}"
fi

# Проверка логов
echo -e "${BLUE}=== Последние логи ===${NC}"
if [[ -f /var/log/xray/error.log ]]; then
    echo "Последние ошибки:"
    tail -n 5 /var/log/xray/error.log 2>/dev/null || echo "Нет ошибок"
else
    echo "Файл логов не найден"
fi

# Проверка Reality ключей
echo -e "${BLUE}=== Reality конфигурация ===${NC}"
if [[ -f /usr/local/etc/xray/config.json ]]; then
    PRIVATE_KEY=$(grep -o '"privateKey": "[^"]*"' /usr/local/etc/xray/config.json | cut -d'"' -f4)
    SHORT_ID=$(grep -o '"shortIds": \[[^]]*\]' /usr/local/etc/xray/config.json | grep -o '"[a-f0-9]*"' | tail -1 | tr -d '"')
    
    echo "Private Key: $PRIVATE_KEY"
    echo "Short ID: $SHORT_ID"
    
    # Генерация публичного ключа
    if command -v xray &> /dev/null && [[ -n "$PRIVATE_KEY" ]]; then
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | xray x25519 -i 2>/dev/null | grep -E "(Public|Password)" | awk '{print $NF}' | tr -d '\r\n ')
        echo "Public Key: $PUBLIC_KEY"
    fi
fi

# Все порты
echo -e "${BLUE}=== Все прослушиваемые порты ===${NC}"
netstat -tlnp

echo -e "${BLUE}=== Диагностика завершена ===${NC}"
EOF

    chmod +x /usr/local/bin/xray-diagnostic.sh
    log "Скрипт диагностики создан: /usr/local/bin/xray-diagnostic.sh"
}

# Основная функция
main() {
    log "Начало автоматической настройки Xray Bot сервера..."
    
    check_root
    install_dependencies
    generate_reality_keys
    create_xray_config
    create_systemd_service
    setup_permissions
    update_bot_env
    start_services
    check_ports
    create_diagnostic_script
    
    log "Настройка завершена успешно!"
    log ""
    log "Следующие шаги:"
    log "1. Обновите BOT_TOKEN и ADMIN_IDS в .env файле"
    log "2. Запустите бота: python3 bot.py"
    log "3. Для диагностики используйте: /usr/local/bin/xray-diagnostic.sh"
    log ""
    log "Reality ключи для бота:"
    log "Private Key: $REALITY_PRIVATE_KEY"
    log "Public Key: $REALITY_PUBLIC_KEY"
    log "Short ID: $REALITY_SHORT_ID"
}

# Запуск
main "$@"
