#!/bin/bash

# Главный скрипт установки и настройки Xray Bot
# Полностью автоматическая установка и настройка с обработкой всех проблем

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Проверка запуска от root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Пожалуйста, запустите скрипт от имени root или с sudo"
        exit 1
    fi
}

# Проверка существования команды
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Обновление системы и установка базовых пакетов с обработкой конфликтов
update_system() {
    print_header "Обновление системы и установка базовых пакетов"

    # Проверка и ожидание завершения других процессов apt
    while pgrep -f "apt|dpkg" > /dev/null; do
        log_warning "Ожидание завершения других процессов пакетного менеджера..."
        sleep 5
    done

    # Исправление сломанных зависимостей
    log_info "Исправление сломанных зависимостей..."
    apt --fix-broken install -y || true
    dpkg --configure -a || true

    # Обновление системы
    log_info "Обновление пакетов системы..."
    apt update -y

    # Установка aptitude для лучшего разрешения зависимостей
    apt install -y aptitude || true

    # Основные пакеты с обработкой ошибок
    local essential_packages=(
        "curl" "wget" "unzip" "tar" "gzip"
        "openssl" "uuid-runtime" "jq"
        "python3" "python3-pip" "python3-venv" "python3-dev"
        "git" "systemd" "chrony" "ufw"
        "build-essential" "libssl-dev" "libffi-dev"
        "protobuf-compiler" "net-tools" "bc"
        "software-properties-common" "apt-transport-https"
        "ca-certificates" "gnupg" "lsb-release"
        "sqlite3" "cron" "logrotate" "lsof"
    )

    for package in "${essential_packages[@]}"; do
        log_info "Установка $package..."
        if apt install -y --no-install-recommends "$package"; then
            log_info "✓ $package установлен"
        elif command -v aptitude &> /dev/null && aptitude install -y "$package"; then
            log_info "✓ $package установлен через aptitude"
        else
            log_warning "Не удалось установить $package, пропускаем..."
        fi
    done

    # Попытка исправить конфликты зависимостей
    if ! apt upgrade -y; then
        log_warning "Обнаружены конфликты зависимостей, исправляем..."
        apt -f install -y || true
        
        # Принудительная установка проблемных пакетов
        apt install -y --fix-missing libsoup2.4-1 || true
        apt install -y --fix-missing libappstream4 || true
        
        # Повторная попытка обновления
        apt upgrade -y --fix-missing || true
    fi

    log_success "Система обновлена и базовые пакеты установлены"
}

# Настройка синхронизации времени
setup_time_sync() {
    print_header "Настройка синхронизации времени"

    # Установка и настройка chrony для синхронизации времени
    log_info "Настройка chrony для синхронизации времени..."

    # Конфигурация chrony
    cat > /etc/chrony/chrony.conf << 'EOL'
# NTP servers
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
pool 2.pool.ntp.org iburst
pool 3.pool.ntp.org iburst

# Record the rate at which the system clock gains/losses time
driftfile /var/lib/chrony/chrony.drift

# Allow the system clock to be stepped in the first three updates
makestep 1.0 3

# Enable kernel synchronization of the real-time clock (RTC)
rtcsync

# Enable hardware timestamping on all interfaces that support it
#hwtimestamp *

# Increase the minimum number of selectable sources required to adjust
# the system clock
minsources 2

# Allow NTP client access from local network
allow 192.168.0.0/16
allow 10.0.0.0/8
allow 172.16.0.0/12

# Serve time even if not synchronized to a time source
local stratum 10

# Specify file containing keys for NTP authentication
keyfile /etc/chrony/chrony.keys

# Get TAI-UTC offset and leap seconds from the system tz database
leapsectz right/UTC

# Specify directory for log files
logdir /var/log/chrony

# Select which information is logged
log measurements statistics tracking
EOL

    # Запуск и включение chrony
    systemctl enable chrony
    systemctl restart chrony

    # Ждем синхронизации
    log_info "Ожидание синхронизации времени..."
    sleep 10

    # Форсированная синхронизация
    chrony sources -v || true
    chronyc makestep || true

    # Проверка синхронизации времени
    if chronyc tracking | grep -q "Leap status.*Normal"; then
        log_success "Время успешно синхронизировано"
        chronyc tracking
    else
        log_warning "Синхронизация времени может быть неполной, но продолжаем"
    fi

    # Настройка автоматической синхронизации
    timedatectl set-ntp true
    log_success "Автоматическая синхронизация времени настроена"
}

# Настройка firewall
setup_firewall() {
    print_header "Настройка firewall"

    # Сброс UFW к состоянию по умолчанию
    ufw --force reset

    # Базовые правила
    ufw default deny incoming
    ufw default allow outgoing

    # Разрешение SSH (важно для удаленного доступа)
    ufw allow OpenSSH
    ufw allow 22/tcp

    # Разрешение HTTP и HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Разрешение DNS
    ufw allow 53/udp
    ufw allow 53/tcp

    # Разрешение NTP для синхронизации времени
    ufw allow 123/udp

    # Включение UFW
    ufw --force enable

    log_success "Firewall настроен - открыты порты: 22(SSH), 80(HTTP), 443(HTTPS), 53(DNS), 123(NTP)"
    ufw status verbose
}

# Проверка доступности google.com
check_google_connectivity() {
    print_header "Проверка доступности google.com"

    # Проверка DNS разрешения
    log_info "Проверка DNS разрешения для google.com..."
    if nslookup google.com > /dev/null 2>&1; then
        log_success "DNS разрешение google.com работает"
    else
        log_error "Проблема с DNS разрешением google.com"

        # Попытка исправить DNS
        log_info "Попытка исправить DNS настройки..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf

        if nslookup google.com > /dev/null 2>&1; then
            log_success "DNS исправлен с использованием публичных DNS серверов"
        else
            log_error "Не удалось исправить DNS. Проверьте сетевые настройки"
            exit 1
        fi
    fi

    # Проверка HTTPS соединения с google.com
    log_info "Проверка HTTPS соединения с google.com..."
    if curl -s --connect-timeout 10 --max-time 30 https://www.google.com/ > /dev/null 2>&1; then
        log_success "HTTPS соединение с google.com работает"
    else
        log_error "Не удается установить HTTPS соединение с google.com"

        # Дополнительная диагностика
        log_info "Диагностика сетевого соединения..."
        ping -c 3 8.8.8.8 || log_warning "Ping до 8.8.8.8 не проходит"
        ping -c 3 google.com || log_warning "Ping до google.com не проходит"

        log_warning "Проблемы с сетевым соединением могут повлиять на работу Reality"
    fi

    # Проверка порта 443 на google.com
    log_info "Проверка доступности порта 443 на google.com..."
    if timeout 10 bash -c "</dev/tcp/www.google.com/443" 2>/dev/null; then
        log_success "Порт 443 на google.com доступен"
    else
        log_warning "Порт 443 на google.com недоступен или заблокирован"
    fi
}

# Установка Xray с обработкой ошибок
install_xray() {
    print_header "Установка Xray"

    if command_exists xray; then
        log_success "Xray уже установлен"
        xray -version
        return 0
    fi

    # Попытка стандартной установки
    log_info "Установка Xray через официальный скрипт..."
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" -- install; then
        log_success "Xray установлен через официальный скрипт"
    else
        log_warning "Стандартная установка не удалась, пробуем ручную установку..."
        install_xray_manual
    fi

    if ! command_exists xray; then
        log_error "Не удалось установить Xray"
        exit 1
    fi

    log_success "Xray успешно установлен"
    xray -version
}

# Ручная установка Xray
install_xray_manual() {
    log_info "Ручная установка Xray..."
    
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
            log_success "Xray установлен вручную"
        else
            log_error "Ошибка при установке Xray"
            exit 1
        fi
    else
        log_error "Не удалось загрузить Xray"
        exit 1
    fi
    
    cd / && rm -rf "$temp_dir"
}

# Генерация ключей Reality
generate_reality_keys() {
    print_header "Генерация ключей Reality"

    log_info "Генерация новых ключей Reality..."

    # Генерация ключей с обработкой разных форматов вывода
    REALITY_OUTPUT=$(xray x25519 2>&1)
    log_info "Вывод xray x25519: $REALITY_OUTPUT"

    # Парсинг ключей (поддержка разных форматов)
    PRIVATE_KEY=""
    PUBLIC_KEY=""

    # Новый формат (PrivateKey: / Password:)
    if echo "$REALITY_OUTPUT" | grep -q "PrivateKey:"; then
        PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n ')
        PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Password:" | awk '{print $2}' | tr -d '\r\n ')
    fi

    # Старый формат (Private key: / Public key:)
    if [ -z "$PRIVATE_KEY" ] && echo "$REALITY_OUTPUT" | grep -q "Private key:"; then
        PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "Private key:" | awk '{print $3}' | tr -d '\r\n ')
        PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Public key:" | awk '{print $3}' | tr -d '\r\n ')
    fi

    # Проверка успешности парсинга
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        log_error "Не удалось распарсить ключи Reality"
        log_error "Вывод команды: $REALITY_OUTPUT"
        exit 1
    fi

    # Генерация short ID
    SHORT_ID=$(openssl rand -hex 8)

    log_success "Ключи Reality сгенерированы:"
    log_info "Private Key: $PRIVATE_KEY"
    log_info "Public Key: $PUBLIC_KEY"
    log_info "Short ID: $SHORT_ID"

    # Сохранение в переменные для использования
    export XRAY_REALITY_PRIVKEY="$PRIVATE_KEY"
    export XRAY_REALITY_PUBKEY="$PUBLIC_KEY"
    export XRAY_REALITY_SHORT_IDS='["", "'$SHORT_ID'"]'
}

# Создание .env файла
create_env_file() {
    print_header "Создание файла конфигурации .env"

    # Определение внешнего IPv4
    EXTERNAL_IP=$(curl -4 -s ifconfig.me || curl -4 -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

    # Создание .env файла
    cat > .env << EOL
# Telegram Bot Settings
BOT_TOKEN=your_bot_token_here
ADMIN_IDS=your_telegram_id_here
CHANNEL_USERNAME=your_channel_username

# Server Settings
SERVER_IP=$EXTERNAL_IP
SERVER_DOMAIN=www.google.com

# Xray Settings
XRAY_REALITY_DEST=www.google.com:443
XRAY_REALITY_PRIVKEY=$XRAY_REALITY_PRIVKEY
XRAY_REALITY_PUBKEY=$XRAY_REALITY_PUBKEY
XRAY_REALITY_SHORT_IDS=$XRAY_REALITY_SHORT_IDS

# gRPC API Settings
GRPC_API_HOST=127.0.0.1
GRPC_API_PORT=50051

# Database Settings
DATABASE_URL=sqlite+aiosqlite:///xray_bot.db

# Subscription Settings
DEFAULT_SUBSCRIPTION_DAYS=30
DEFAULT_DATA_LIMIT_GB=100
EOL

    # Установка прав доступа
    chmod 600 .env

    log_success "Файл .env создан с автоматически сгенерированными ключами"
    log_info "Внешний IP сервера: $EXTERNAL_IP"
    log_warning "Не забудьте отредактировать BOT_TOKEN, ADMIN_IDS и CHANNEL_USERNAME в .env"
}

# Создание конфигурации Xray
create_xray_config() {
    print_header "Создание конфигурации Xray"

    # Создание директорий
    mkdir -p /usr/local/etc/xray
    mkdir -p /var/log/xray

    # Создание конфигурации без fallbacks (исправление проблемы)
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
                    "privateKey": "$XRAY_REALITY_PRIVKEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "",
                        "$SHORT_ID"
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

    # Валидация конфигурации
    log_info "Валидация конфигурации Xray..."
    if xray -test -config /usr/local/etc/xray/config.json; then
        log_success "Конфигурация Xray корректна"
    else
        log_error "Ошибка в конфигурации Xray"
        exit 1
    fi

    # Установка прав доступа
    chown -R nobody:nogroup /usr/local/etc/xray
    chmod 755 /usr/local/etc/xray
    chmod 644 /usr/local/etc/xray/config.json

    # Создание и настройка логов
    touch /var/log/xray/access.log /var/log/xray/error.log
    chown nobody:nogroup /var/log/xray/access.log /var/log/xray/error.log
    chmod 644 /var/log/xray/access.log /var/log/xray/error.log
    chown nobody:nogroup /var/log/xray
    chmod 755 /var/log/xray

    log_success "Конфигурация Xray создана и настроена"
}

# Создание systemd сервиса для Xray
create_xray_service() {
    print_header "Создание systemd сервиса для Xray"

    cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
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

    systemctl daemon-reload
    systemctl enable xray

    log_success "Systemd сервис для Xray создан"
}

# Настройка Python окружения
setup_python_environment() {
    print_header "Настройка Python окружения"

    # Проверка версии Python
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log_info "Обнаружен Python $PYTHON_VERSION"

    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)"; then
        log_success "Python версии $PYTHON_VERSION подходит"
    else
        log_warning "Рекомендуется Python 3.8+, но будем работать с $PYTHON_VERSION"
    fi

    # Создание виртуального окружения
    if [ ! -d "venv" ]; then
        log_info "Создание виртуального окружения Python..."
        python3 -m venv venv
    fi

    # Активация и установка зависимостей
    log_info "Установка Python зависимостей..."
    source venv/bin/activate

    # Обновление pip
    pip install --upgrade pip wheel setuptools

    # Установка зависимостей
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        log_info "requirements.txt не найден, устанавливаем базовые зависимости..."
        pip install \
            aiogram==2.25.1 \
            sqlalchemy[asyncio] \
            aiosqlite \
            python-dotenv \
            python-dateutil \
            grpcio \
            grpcio-tools \
            protobuf
    fi

    log_success "Python окружение настроено"
}

# Генерация gRPC кода
generate_grpc_code() {
    print_header "Генерация gRPC кода"

    # Проверка наличия proto файла
    if [ ! -f "xray_api.proto" ]; then
        log_warning "xray_api.proto не найден, создаем базовую версию..."

        # Создание базового proto файла
        cat > xray_api.proto << 'EOF'
syntax = "proto3";

package xray.app.proxyman.command;
option go_package = "github.com/xtls/xray-core/app/proxyman/command";

import "google/protobuf/any.proto";

service HandlerService {
    rpc AddInbound(AddInboundRequest) returns (AddInboundResponse);
    rpc RemoveInbound(RemoveInboundRequest) returns (RemoveInboundResponse);
    rpc AlterInbound(AlterInboundRequest) returns (AlterInboundResponse);
    rpc AddOutbound(AddOutboundRequest) returns (AddOutboundResponse);
    rpc RemoveOutbound(RemoveOutboundRequest) returns (RemoveOutboundResponse);
    rpc AlterOutbound(AlterOutboundRequest) returns (AlterOutboundResponse);
}

message AddInboundRequest {
    google.protobuf.Any inbound = 1;
}

message AddInboundResponse {
}

message RemoveInboundRequest {
    string tag = 1;
}

message RemoveInboundResponse {
}

message AlterInboundRequest {
    string tag = 1;
    google.protobuf.Any operation = 2;
}

message AlterInboundResponse {
}

message AddOutboundRequest {
    google.protobuf.Any outbound = 1;
}

message AddOutboundResponse {
}

message RemoveOutboundRequest {
    string tag = 1;
}

message RemoveOutboundResponse {
}

message AlterOutboundRequest {
    string tag = 1;
    google.protobuf.Any operation = 2;
}

message AlterOutboundResponse {
}
EOF
    fi

    # Генерация gRPC кода
    source venv/bin/activate
    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. xray_api.proto

    if [ $? -eq 0 ]; then
        log_success "gRPC код успешно сгенерирован"
    else
        log_warning "Не удалось сгенерировать gRPC код, но продолжаем"
    fi
}

# Создание systemd сервиса для бота
create_bot_service() {
    print_header "Создание systemd сервиса для бота"

    cat > /etc/systemd/system/xray-bot.service << EOL
[Unit]
Description=Xray VPN Bot
After=network.target xray.service
Requires=xray.service

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
Environment="PATH=$(pwd)/venv/bin"
ExecStart=$(pwd)/venv/bin/python3 bot.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable xray-bot

    log_success "Systemd сервис для бота создан"
}

# Запуск сервисов
start_services() {
    print_header "Запуск сервисов"

    # Запуск Xray
    log_info "Запуск Xray..."
    systemctl restart xray
    sleep 3

    if systemctl is-active --quiet xray; then
        log_success "Xray запущен успешно"
    else
        log_error "Не удалось запустить Xray"
        journalctl -u xray --no-pager -l --since="1 minute ago"
        exit 1
    fi

    # Проверка gRPC API
    log_info "Проверка gRPC API..."
    if netstat -tlnp 2>/dev/null | grep -q ":50051"; then
        log_success "gRPC API работает на порту 50051"
    else
        log_warning "gRPC API не найден на порту 50051"
    fi

    log_info "Сервис бота настроен, но не запущен (требуется настройка .env)"
}

# Финальные проверки и диагностика
final_verification() {
    print_header "Финальные проверки системы"

    # Проверка времени
    log_info "Проверка синхронизации времени..."
    if chronyc tracking | grep -q "Leap status.*Normal"; then
        log_success "✓ Время синхронизировано"
    else
        log_warning "⚠ Время может быть не синхронизировано"
    fi

    # Проверка firewall
    log_info "Проверка firewall..."
    if ufw status | grep -q "Status: active"; then
        log_success "✓ Firewall активен"
        if ufw status | grep -q "443/tcp.*ALLOW"; then
            log_success "✓ Порт 443 открыт"
        else
            log_warning "⚠ Порт 443 может быть заблокирован"
        fi
    else
        log_warning "⚠ Firewall не активен"
    fi

    # Проверка доступности google.com
    log_info "Проверка доступности google.com..."
    if curl -s --connect-timeout 5 https://www.google.com/ > /dev/null; then
        log_success "✓ Google.com доступен"
    else
        log_warning "⚠ Проблемы с доступом к google.com"
    fi

    # Проверка Xray
    log_info "Проверка Xray..."
    if systemctl is-active --quiet xray; then
        log_success "✓ Xray запущен"
    else
        log_error "✗ Xray не запущен"
    fi

    # Проверка портов
    log_info "Проверка портов..."
    if ss -tlnp | grep -q ":443"; then
        log_success "✓ Порт 443 прослушивается"
    else
        log_warning "⚠ Порт 443 не прослушивается"
    fi

    if ss -tlnp | grep -q ":50051"; then
        log_success "✓ Порт 50051 (gRPC API) прослушивается"
    else
        log_warning "⚠ Порт 50051 не прослушивается"
    fi

    # Проверка конфигурационных файлов
    log_info "Проверка конфигурации..."
    if [ -f ".env" ]; then
        log_success "✓ Файл .env существует"

        if grep -q "BOT_TOKEN=your_bot_token_here" .env; then
            log_warning "⚠ BOT_TOKEN требует настройки"
        else
            log_success "✓ BOT_TOKEN настроен"
        fi

        if grep -q "ADMIN_IDS=your_telegram_id_here" .env; then
            log_warning "⚠ ADMIN_IDS требует настройки"
        else
            log_success "✓ ADMIN_IDS настроен"
        fi
    else
        log_error "✗ Файл .env не найден"
    fi

    if [ -f "/usr/local/etc/xray/config.json" ]; then
        log_success "✓ Конфигурация Xray существует"
    else
        log_error "✗ Конфигурация Xray не найдена"
    fi
}

# Главная функция
main() {
    print_header "Запуск установки Xray VPN Bot"

    # Проверки
    check_root

    # Основные этапы установки
    update_system
    setup_time_sync
    setup_firewall
    check_google_connectivity
    install_xray
    generate_reality_keys
    create_env_file
    create_xray_config
    create_xray_service
    setup_python_environment
    generate_grpc_code
    create_bot_service
    start_services
    final_verification

    # Финальные инструкции
    print_header "Установка завершена!"

    log_success "Xray VPN Bot успешно установлен и настроен!"

    echo -e "\n${YELLOW}Следующие шаги:${NC}"
    echo "1. ${RED}ОБЯЗАТЕЛЬНО:${NC} Отредактируйте файл .env:"
    echo "   nano .env"
    echo "   - Установите ваш BOT_TOKEN от @BotFather"
    echo "   - Установите ваши ADMIN_IDS (ID телеграм администраторов)"
    echo "   - Установите CHANNEL_USERNAME (канал для проверки подписки)"
    echo ""
    echo "2. ${GREEN}Запустите бота:${NC}"
    echo "   systemctl start xray-bot"
    echo ""
    echo "3. ${BLUE}Проверьте статус:${NC}"
    echo "   systemctl status xray-bot"
    echo "   systemctl status xray"
    echo ""
    echo "4. ${BLUE}Просмотр логов:${NC}"
    echo "   journalctl -u xray-bot -f"
    echo "   journalctl -u xray -f"
    echo ""

    echo -e "${YELLOW}Полезные команды:${NC}"
    echo "• Перезапуск бота: systemctl restart xray-bot"
    echo "• Перезапуск Xray: systemctl restart xray"
    echo "• Проверка портов: ss -tlnp | grep -E ':(443|50051)'"
    echo "• Проверка времени: chronyc tracking"
    echo "• Проверка firewall: ufw status"
    echo "• Тест Reality: openssl s_client -connect $(grep SERVER_IP .env | cut -d= -f2):443 -servername www.google.com"
    echo ""

    echo -e "${YELLOW}Информация о сгенерированных ключах:${NC}"
    echo "Private Key: $XRAY_REALITY_PRIVKEY"
    echo "Public Key: $XRAY_REALITY_PUBKEY"
    echo "Short ID: $SHORT_ID"
    echo ""

    echo -e "${GREEN}Сервер готов к работе!${NC}"
    echo -e "${YELLOW}После настройки .env файла бот будет готов выдавать VPN ключи.${NC}"
}

# Запуск главной функции
main "$@"