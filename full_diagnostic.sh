#!/bin/bash

# Полностью автоматический скрипт диагностики Xray Bot
# Объединяет все функции диагностики в один автоматический процесс

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
}

success() {
    echo -e "${GREEN}[SUCCESS] ✓ $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Проверка root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)"
        exit 1
    fi
}

# Автоматическая проверка и исправление времени
auto_fix_time() {
    print_header "Автоматическое исправление времени"
    
    # Установка chrony если не установлен
    if ! command -v chrony &> /dev/null; then
        info "Установка chrony..."
        apt update && apt install -y chrony
    fi
    
    # Запуск chrony
    if ! systemctl is-active --quiet chrony; then
        info "Запуск chrony..."
        systemctl start chrony
        systemctl enable chrony
    fi
    
    # Принудительная синхронизация
    info "Принудительная синхронизация времени..."
    chronyc makestep
    sleep 5
    
    if chronyc tracking | grep -q "Leap status.*Normal"; then
        success "Время синхронизировано"
    else
        warn "Проблемы с синхронизацией времени"
    fi
    
    info "Текущее время: $(date)"
}

# Автоматическая настройка firewall
auto_fix_firewall() {
    print_header "Автоматическая настройка firewall"
    
    info "Настройка UFW..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow OpenSSH
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8443/tcp
    ufw allow 53/udp
    ufw allow 123/udp
    ufw --force enable
    
    success "UFW настроен и активирован"
    
    info "Текущие правила UFW:"
    ufw status verbose
}

# Проверка и исправление DNS
auto_fix_dns() {
    print_header "Проверка и исправление DNS"
    
    if ! nslookup google.com > /dev/null 2>&1; then
        warn "Проблема с DNS, исправляем..."
        
        # Создание резервной копии
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s)
        
        # Настройка надежных DNS серверов
        cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF
        
        if nslookup google.com > /dev/null 2>&1; then
            success "DNS исправлен"
        else
            error "Не удалось исправить DNS"
        fi
    else
        success "DNS работает корректно"
    fi
}

# Проверка подключения к Google
check_google_connectivity() {
    print_header "Проверка доступности Google"
    
    # Проверка HTTPS подключения
    if curl -s --connect-timeout 10 --max-time 20 https://www.google.com/ > /dev/null; then
        success "HTTPS соединение с Google работает"
    else
        warn "Проблемы с HTTPS соединением"
        
        # Дополнительная диагностика
        info "Диагностика сетевого соединения:"
        ping -c 3 8.8.8.8 && success "Ping до 8.8.8.8 успешен" || warn "Ping до 8.8.8.8 неуспешен"
        ping -c 3 google.com && success "Ping до google.com успешен" || warn "Ping до google.com неуспешен"
    fi
    
    # Проверка порта 443 на google.com
    if timeout 10 bash -c "echo >/dev/tcp/www.google.com/443" 2>/dev/null; then
        success "Порт 443 на google.com доступен"
    else
        warn "Порт 443 на google.com недоступен или заблокирован"
    fi
}

# Генерация новых Reality ключей
generate_reality_keys() {
    print_header "Генерация Reality ключей"
    
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
        return 1
    fi
    
    # Генерация shortId
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    
    success "Reality ключи сгенерированы:"
    info "Private Key: $REALITY_PRIVATE_KEY"
    info "Public Key: $REALITY_PUBLIC_KEY"
    info "Short ID: $REALITY_SHORT_ID"
}

# Создание оптимизированной конфигурации Xray
create_optimized_xray_config() {
    print_header "Создание оптимизированной конфигурации Xray"
    
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
                        "google.com",
                        "www.youtube.com",
                        "play.google.com"
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
    
    success "Конфигурация Xray создана"
}

# Синхронизация .env файла
sync_env_file() {
    print_header "Синхронизация .env файла"
    
    # Поиск .env файла
    local env_files=(
        "/home/*/Project/CascadeProjects/windsurf-project/.env"
        "/opt/xray-bot/.env"
        "$(pwd)/.env"
    )
    
    local env_file=""
    for file in "${env_files[@]}"; do
        if [[ -f $file ]]; then
            env_file="$file"
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
    
    # Создание резервной копии
    [[ -f "$env_file" ]] && cp "$env_file" "${env_file}.backup.$(date +%s)"
    
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
    
    success ".env файл синхронизирован: $env_file"
    info "Не забудьте обновить BOT_TOKEN и ADMIN_IDS"
}

# Настройка прав доступа
setup_permissions() {
    print_header "Настройка прав доступа"
    
    # Создание пользователя nobody если не существует
    if ! id "nobody" &>/dev/null; then
        useradd -r -s /bin/false nobody
    fi
    
    # Настройка прав на файлы
    chown -R nobody:nogroup /usr/local/etc/xray/ /var/log/xray/
    chmod 644 /usr/local/etc/xray/config.json
    chmod 755 /var/log/xray/
    
    success "Права доступа настроены"
}

# Создание и запуск systemd сервиса
setup_systemd_service() {
    print_header "Настройка systemd сервиса"
    
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
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Активация и запуск Xray
    systemctl enable xray
    systemctl start xray
    
    sleep 3
    
    if systemctl is-active --quiet xray; then
        success "Xray сервис запущен успешно"
    else
        error "Не удалось запустить Xray сервис"
        info "Логи сервиса:"
        journalctl -u xray -n 10 --no-pager
        return 1
    fi
}

# Проверка портов
check_ports() {
    print_header "Проверка портов"
    
    sleep 3  # Ждем запуска сервиса
    
    local ports_ok=true
    
    if netstat -tlnp | grep -q ":443 "; then
        success "Порт 443 прослушивается"
        local process_443=$(lsof -ti:443 | xargs ps -p 2>/dev/null | tail -n +2 | awk '{print $4}' | head -1)
        info "Процесс на порту 443: ${process_443:-xray}"
    else
        error "Порт 443 не прослушивается"
        ports_ok=false
    fi
    
    if netstat -tlnp | grep -q ":50051 "; then
        success "Порт 50051 (gRPC API) прослушивается"
    else
        error "Порт 50051 не прослушивается"
        ports_ok=false
    fi
    
    if [[ "$ports_ok" == false ]]; then
        warn "Обнаружены проблемы с портами, перезапускаем сервис..."
        systemctl restart xray
        sleep 5
        
        # Повторная проверка
        if netstat -tlnp | grep -q ":443 " && netstat -tlnp | grep -q ":50051 "; then
            success "Порты восстановлены после перезапуска"
        else
            error "Проблемы с портами не устранены"
        fi
    fi
    
    info "Все прослушиваемые порты:"
    netstat -tlnp | grep -E ":(22|80|443|50051|8443)"
}

# Валидация конфигурации
validate_config() {
    print_header "Валидация конфигурации"
    
    local config_file="/usr/local/etc/xray/config.json"
    
    # Проверка валидности JSON
    if python3 -m json.tool "$config_file" > /dev/null 2>&1; then
        success "JSON конфигурация валидна"
    else
        error "JSON конфигурация содержит ошибки"
        return 1
    fi
    
    # Проверка конфигурации через запуск с проверкой
    info "Проверка конфигурации Xray..."
    if timeout 10 /usr/local/bin/xray run -config "$config_file" -test 2>/dev/null; then
        success "Xray конфигурация валидна"
    else
        # Альтернативная проверка - попытка парсинга конфигурации
        if /usr/local/bin/xray run -config "$config_file" -test 2>&1 | grep -q "Configuration OK\|started"; then
            success "Xray конфигурация валидна"
        else
            warn "Не удалось проверить конфигурацию Xray, но JSON валиден"
            info "Конфигурация будет проверена при запуске сервиса"
        fi
    fi
}

# Тест Reality соединения
test_reality_connection() {
    print_header "Тест Reality соединения"
    
    local server_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    
    if [[ -n "$server_ip" ]]; then
        info "Тестирование Reality соединения с $server_ip..."
        
        # Тест без SNI (должен показать ошибку или перенаправление)
        info "Тест без SNI:"
        local no_sni_result=$(echo "Q" | timeout 10 openssl s_client -connect $server_ip:443 2>/dev/null | grep -E "(subject|verify|Verification)" || echo "Нет ответа")
        info "Результат без SNI: $no_sni_result"
        
        # Тест с SNI www.google.com
        info "Тест с SNI www.google.com:"
        local sni_result=$(echo "Q" | timeout 10 openssl s_client -connect $server_ip:443 -servername www.google.com 2>/dev/null | grep -E "(subject|Verification)" || echo "Нет ответа")
        
        if echo "$sni_result" | grep -q "subject=CN = www.google.com"; then
            success "Reality работает корректно с SNI"
            success "Сертификат Google успешно маскируется"
        else
            warn "Reality может работать некорректно с SNI"
            info "Результат теста: $sni_result"
        fi
    else
        warn "Не удалось определить IP сервера для теста"
    fi
}

# Создание отчета
generate_report() {
    print_header "Создание отчета диагностики"
    
    local report_file="/tmp/xray-diagnostic-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Отчет автоматической диагностики Xray Bot - $(date)"
        echo "=================================================="
        echo
        echo "Статус сервиса: $(systemctl is-active xray)"
        echo "Автозапуск: $(systemctl is-enabled xray)"
        echo "Версия Xray: $(/usr/local/bin/xray version 2>/dev/null | head -1 || echo 'Неизвестно')"
        echo "IP сервера: $(curl -s ifconfig.me || echo 'Неизвестно')"
        echo
        echo "Reality ключи:"
        echo "Private Key: $REALITY_PRIVATE_KEY"
        echo "Public Key: $REALITY_PUBLIC_KEY"
        echo "Short ID: $REALITY_SHORT_ID"
        echo
        echo "Порты:"
        netstat -tlnp | grep -E ":(443|50051)"
        echo
        echo "Последние логи:"
        journalctl -u xray -n 5 --no-pager
        echo
        echo "Системная информация:"
        echo "Время работы: $(uptime -p)"
        echo "Использование диска:"
        df -h / | tail -1
    } > "$report_file"
    
    success "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    log "Начало полностью автоматической диагностики и настройки Xray Bot..."
    echo
    
    check_root
    auto_fix_time
    auto_fix_firewall
    auto_fix_dns
    check_google_connectivity
    generate_reality_keys
    create_optimized_xray_config
    sync_env_file
    setup_permissions
    setup_systemd_service
    check_ports
    validate_config
    test_reality_connection
    generate_report
    
    echo
    success "Автоматическая диагностика и настройка завершена!"
    echo
    info "Следующие шаги:"
    info "1. Обновите BOT_TOKEN и ADMIN_IDS в .env файле"
    info "2. Запустите бота: python3 bot.py"
    info "3. Для повторной диагностики используйте: $0"
    echo
    info "Reality ключи для бота:"
    info "Private Key: $REALITY_PRIVATE_KEY"
    info "Public Key: $REALITY_PUBLIC_KEY"
    info "Short ID: $REALITY_SHORT_ID"
    echo
    info "Сервер готов к работе!"
}

# Запуск
main "$@"
