#!/bin/bash

# Диагностический скрипт для Xray VPN Bot
# Автоматическая диагностика и исправление проблем

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Проверка времени и исправление
check_time_sync() {
    print_header "Проверка синхронизации времени"

    # Статус chrony
    if systemctl is-active --quiet chrony; then
        log_success "Chrony активен"
    else
        log_warning "Chrony не активен, запускаем..."
        systemctl start chrony
        sleep 5
    fi

    # Проверка синхронизации
    if chronyc tracking | grep -q "Leap status.*Normal"; then
        log_success "✓ Время синхронизировано"
    else
        log_warning "⚠ Время не синхронизировано, принудительно синхронизируем..."
        chronyc makestep
        sleep 10

        if chronyc tracking | grep -q "Leap status.*Normal"; then
            log_success "✓ Время принудительно синхронизировано"
        else
            log_error "✗ Не удалось синхронизировать время"
        fi
    fi

    # Показать текущее время и сдвиг
    echo "Текущее время: $(date)"
    echo "Информация о синхронизации:"
    chronyc tracking
}

# Проверка и исправление firewall
check_firewall() {
    print_header "Проверка firewall"

    if ufw status | grep -q "Status: active"; then
        log_success "✓ UFW активен"

        # Проверка порта 443
        if ufw status | grep -q "443/tcp.*ALLOW"; then
            log_success "✓ Порт 443 разрешен"
        else
            log_warning "⚠ Порт 443 не разрешен, исправляем..."
            ufw allow 443/tcp
            log_success "✓ Порт 443 разрешен"
        fi

        # Проверка SSH
        if ufw status | grep -q "22/tcp.*ALLOW\|OpenSSH.*ALLOW"; then
            log_success "✓ SSH разрешен"
        else
            log_warning "⚠ SSH не разрешен, исправляем..."
            ufw allow OpenSSH
            log_success "✓ SSH разрешен"
        fi
    else
        log_warning "⚠ UFW не активен, настраиваем..."
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow OpenSSH
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 53/udp
        ufw allow 123/udp
        ufw --force enable
        log_success "✓ UFW настроен и активирован"
    fi

    echo "Текущие правила UFW:"
    ufw status verbose
}

# Проверка подключения к Google
check_google_connectivity() {
    print_header "Проверка доступности Google"

    # DNS разрешение
    if nslookup google.com > /dev/null 2>&1; then
        log_success "✓ DNS разрешение google.com работает"
    else
        log_warning "⚠ Проблема с DNS, исправляем..."
        # Временное исправление DNS
        echo "nameserver 8.8.8.8" > /etc/resolv.conf.new
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf.new
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf.new
        mv /etc/resolv.conf.new /etc/resolv.conf

        if nslookup google.com > /dev/null 2>&1; then
            log_success "✓ DNS исправлен"
        else
            log_error "✗ Не удалось исправить DNS"
        fi
    fi

    # HTTPS подключение
    if curl -s --connect-timeout 10 --max-time 20 https://www.google.com/ > /dev/null; then
        log_success "✓ HTTPS соединение с Google работает"
    else
        log_warning "⚠ Проблемы с HTTPS соединением"

        # Дополнительная диагностика
        echo "Диагностика сетевого соединения:"
        ping -c 3 8.8.8.8 && log_info "Ping до 8.8.8.8 успешен" || log_warning "Ping до 8.8.8.8 неуспешен"
        ping -c 3 google.com && log_info "Ping до google.com успешен" || log_warning "Ping до google.com неуспешен"
    fi

    # Проверка порта 443 на google.com
    if timeout 10 bash -c "echo >/dev/tcp/www.google.com/443" 2>/dev/null; then
        log_success "✓ Порт 443 на google.com доступен"
    else
        log_warning "⚠ Порт 443 на google.com недоступен или заблокирован"
    fi
}

# Проверка статуса сервисов
check_services() {
    print_header "Проверка сервисов"

    # Проверка Xray
    if systemctl is-active --quiet xray; then
        log_success "✓ Xray сервис работает"
    else
        log_warning "⚠ Xray не работает, попытка перезапуска..."
        systemctl restart xray
        sleep 5

        if systemctl is-active --quiet xray; then
            log_success "✓ Xray перезапущен успешно"
        else
            log_error "✗ Не удалось запустить Xray"
            echo "Последние логи Xray:"
            journalctl -u xray --no-pager -l --since="5 minutes ago"
        fi
    fi

    # Проверка бота
    if systemctl is-active --quiet xray-bot; then
        log_success "✓ Bot сервис работает"
    else
        log_warning "⚠ Bot не работает"

        # Проверка конфигурации
        if [ -f ".env" ] && ! grep -q "BOT_TOKEN=your_bot_token_here" .env; then
            log_info "Конфигурация выглядит настроенной, попытка запуска..."
            systemctl restart xray-bot
            sleep 5

            if systemctl is-active --quiet xray-bot; then
                log_success "✓ Bot перезапущен успешно"
            else
                log_error "✗ Не удалось запустить Bot"
                echo "Последние логи Bot:"
                journalctl -u xray-bot --no-pager -l --since="5 minutes ago"
            fi
        else
            log_warning "Bot требует настройки BOT_TOKEN в .env файле"
        fi
    fi
}

# Проверка портов
check_ports() {
    print_header "Проверка портов"

    # Порт 443 (Xray)
    if ss -tlnp | grep -q ":443"; then
        log_success "✓ Порт 443 прослушивается"
        XRAY_PID=$(ss -tlnp | grep ":443" | grep -o 'pid=[0-9]*' | cut -d= -f2)
        if [ -n "$XRAY_PID" ]; then
            log_info "Процесс на порту 443: $(ps -p $XRAY_PID -o comm= || echo 'неизвестен')"
        fi
    else
        log_error "✗ Порт 443 не прослушивается"
        log_info "Проверяем, не занят ли порт другим процессом..."

        # Поиск процессов на порту 443
        if lsof -i :443 > /dev/null 2>&1; then
            log_warning "Порт 443 занят другим процессом:"
            lsof -i :443
        else
            log_info "Порт 443 свободен, проблема в конфигурации Xray"
        fi
    fi

    # Порт 50051 (gRPC API)
    if ss -tlnp | grep -q ":50051"; then
        log_success "✓ Порт 50051 (gRPC API) прослушивается"
    else
        log_warning "⚠ Порт 50051 не прослушивается"
        log_info "gRPC API может быть недоступен для управления пользователями"
    fi

    # Показать все прослушиваемые порты
    echo "Все прослушиваемые порты:"
    ss -tlnp | grep -E ':(22|80|443|50051)'
}

# Проверка конфигурации Xray
check_xray_config() {
    print_header "Проверка конфигурации Xray"

    if [ -f "/usr/local/etc/xray/config.json" ]; then
        log_success "✓ Конфигурационный файл существует"

        # Валидация конфигурации
        if xray -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1; then
            log_success "✓ Конфигурация Xray корректна"
        else
            log_error "✗ Ошибка в конфигурации Xray"
            echo "Результат валидации:"
            xray -test -config /usr/local/etc/xray/config.json
        fi

        # Проверка ключей Reality
        PRIVATE_KEY=$(grep -o '"privateKey": "[^"]*"' /usr/local/etc/xray/config.json | cut -d'"' -f4)
        if [ -n "$PRIVATE_KEY" ] && [ "$PRIVATE_KEY" != "YOUR_GENERATED_PRIVATE_KEY" ]; then
            log_success "✓ Приватный ключ Reality настроен"
        else
            log_error "✗ Приватный ключ Reality не настроен"
        fi

        # Проверка short IDs
        SHORT_IDS=$(grep -o '"shortIds": \[[^\]]*\]' /usr/local/etc/xray/config.json)
        if [ -n "$SHORT_IDS" ]; then
            log_success "✓ Short IDs настроены: $SHORT_IDS"
        else
            log_warning "⚠ Short IDs не найдены"
        fi

    else
        log_error "✗ Конфигурационный файл Xray не найден"
    fi
}

# Проверка .env файла
check_env_config() {
    print_header "Проверка конфигурации .env"

    if [ -f ".env" ]; then
        log_success "✓ Файл .env существует"

        # Проверка BOT_TOKEN
        if grep -q "BOT_TOKEN=" .env && ! grep -q "BOT_TOKEN=your_bot_token_here" .env; then
            log_success "✓ BOT_TOKEN настроен"
        else
            log_warning "⚠ BOT_TOKEN требует настройки"
        fi

        # Проверка ADMIN_IDS
        if grep -q "ADMIN_IDS=" .env && ! grep -q "ADMIN_IDS=your_telegram_id_here" .env; then
            log_success "✓ ADMIN_IDS настроен"
        else
            log_warning "⚠ ADMIN_IDS требует настройки"
        fi

        # Проверка SERVER_IP
        SERVER_IP=$(grep "SERVER_IP=" .env | cut -d= -f2)
        if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "YOUR_SERVER_IP" ]; then
            log_success "✓ SERVER_IP настроен: $SERVER_IP"
        else
            log_warning "⚠ SERVER_IP требует настройки"
        fi

        # Проверка Reality ключей
        if grep -q "XRAY_REALITY_PRIVKEY=" .env && ! grep -q "XRAY_REALITY_PRIVKEY=$" .env; then
            log_success "✓ Reality ключи настроены"
        else
            log_warning "⚠ Reality ключи не настроены"
        fi

    else
        log_error "✗ Файл .env не найден"
    fi
}

# Тест Reality соединения
test_reality_connection() {
    print_header "Тест Reality соединения"

    if [ -f ".env" ]; then
        SERVER_IP=$(grep "SERVER_IP=" .env | cut -d= -f2)

        if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "YOUR_SERVER_IP" ]; then
            log_info "Тестирование Reality соединения с $SERVER_IP..."

            # Тест без SNI (должен показать ошибку invalid2.invalid)
            log_info "Тест без SNI:"
            NO_SNI_RESULT=$(echo "Q" | timeout 10 openssl s_client -connect $SERVER_IP:443 2>/dev/null | grep -E "(subject|verify|Verification)")
            if echo "$NO_SNI_RESULT" | grep -q "invalid2.invalid"; then
                log_success "✓ Reality корректно скрывает сервер без SNI"
            else
                log_warning "Результат без SNI: $NO_SNI_RESULT"
            fi

            # Тест с различными SNI
            log_info "Тест с SNI www.google.com:"
            SNI_RESULT=$(echo "Q" | timeout 10 openssl s_client -connect $SERVER_IP:443 -servername www.google.com 2>/dev/null | grep -E "(subject|Verification)")
            
            if echo "$SNI_RESULT" | grep -q "subject=CN = www.google.com" && echo "$SNI_RESULT" | grep -q "Verification: OK"; then
                log_success "✓ Reality работает корректно с SNI"
                log_success "✓ Сертификат Google успешно маскируется"
            elif echo "$SNI_RESULT" | grep -q "subject=CN = www.google.com"; then
                log_success "✓ Reality работает корректно (маскировка под Google)"
                log_info "Сертификат Google корректно отображается"
            else
                log_warning "⚠ Reality может работать некорректно с SNI"
                echo "Результат теста:"
                echo "$SNI_RESULT"
            fi
            
            # Дополнительный тест с YouTube SNI
            log_info "Тест с SNI www.youtube.com:"
            YOUTUBE_RESULT=$(echo "Q" | timeout 10 openssl s_client -connect $SERVER_IP:443 -servername www.youtube.com 2>/dev/null | grep -E "(subject|Verification)")
            if echo "$YOUTUBE_RESULT" | grep -q "subject=CN = \\*.youtube.com\|subject=CN = www.youtube.com"; then
                log_success "✓ YouTube SNI также работает корректно"
            else
                log_info "YouTube SNI результат: $YOUTUBE_RESULT"
            fi
        else
            log_warning "SERVER_IP не настроен для теста"
        fi
    else
        log_warning "Файл .env не найден для теста"
    fi
}

# Показать информацию о ключах
show_keys_info() {
    print_header "Информация о Reality ключах"

    if [ -f ".env" ]; then
        echo "Из файла .env:"
        echo "XRAY_REALITY_PRIVKEY=$(grep XRAY_REALITY_PRIVKEY= .env | cut -d= -f2)"
        echo "XRAY_REALITY_PUBKEY=$(grep XRAY_REALITY_PUBKEY= .env | cut -d= -f2)"
        echo "XRAY_REALITY_SHORT_IDS=$(grep XRAY_REALITY_SHORT_IDS= .env | cut -d= -f2)"
        echo ""
    fi

    if [ -f "/usr/local/etc/xray/config.json" ]; then
        echo "Из конфигурации Xray:"
        PRIVATE_KEY=$(grep -o '"privateKey": "[^"]*"' /usr/local/etc/xray/config.json | cut -d'"' -f4)
        SHORT_IDS=$(grep -A5 -B5 shortIds /usr/local/etc/xray/config.json | grep -o '"[a-fA-F0-9]*"' | tr -d '"')
        echo "privateKey: $PRIVATE_KEY"
        echo "shortIds: $SHORT_IDS"
    fi
}

# Исправление проблем
fix_problems() {
    print_header "Автоматическое исправление проблем"

    log_info "Попытка исправления основных проблем..."

    # Исправление времени
    chronyc makestep || true

    # Исправление firewall
    ufw allow 443/tcp || true

    # Перезапуск сервисов
    systemctl restart xray || true
    sleep 5

    if [ -f ".env" ] && ! grep -q "BOT_TOKEN=your_bot_token_here" .env; then
        systemctl restart xray-bot || true
    fi

    log_success "Попытка исправления завершена"
}

# Показать логи
show_logs() {
    print_header "Последние логи сервисов"

    echo -e "${YELLOW}Логи Xray (последние 20 строк):${NC}"
    journalctl -u xray --no-pager -n 20

    echo -e "\n${YELLOW}Логи Bot (последние 20 строк):${NC}"
    journalctl -u xray-bot --no-pager -n 20

    if [ -f "/var/log/xray/error.log" ]; then
        echo -e "\n${YELLOW}Xray error.log (последние 10 строк):${NC}"
        tail -10 /var/log/xray/error.log
    fi
}

# Генерация нового конфига с исправленными ключами
regenerate_config() {
    print_header "Регенерация конфигурации с новыми ключами"

    # Остановить сервисы
    systemctl stop xray || true
    systemctl stop xray-bot || true

    # Проверка версии Xray
    XRAY_VERSION=$(xray -version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    log_info "Версия Xray: $XRAY_VERSION"
    
    # Генерация новых ключей
    log_info "Генерация новых Reality ключей..."
    REALITY_OUTPUT=$(xray x25519 2>&1)

    # Парсинг ключей
    PRIVATE_KEY=""
    PUBLIC_KEY=""

    if echo "$REALITY_OUTPUT" | grep -q "PrivateKey:"; then
        PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n ')
        PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Password:" | awk '{print $2}' | tr -d '\r\n ')
    elif echo "$REALITY_OUTPUT" | grep -q "Private key:"; then
        PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "Private key:" | awk '{print $3}' | tr -d '\r\n ')
        PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Public key:" | awk '{print $3}' | tr -d '\r\n ')
    fi

    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        log_error "Не удалось сгенерировать новые ключи"
        return 1
    fi

    SHORT_ID=$(openssl rand -hex 8)

    log_success "Новые ключи сгенерированы:"
    log_info "Private Key: $PRIVATE_KEY"
    log_info "Public Key: $PUBLIC_KEY"
    log_info "Short ID: $SHORT_ID"

    # Обновление .env
    if [ -f ".env" ]; then
        sed -i "s/XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$PRIVATE_KEY/" .env
        sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" .env
        sed -i "s/XRAY_REALITY_SHORT_IDS=.*/XRAY_REALITY_SHORT_IDS='[\"\", \"$SHORT_ID\"]'/" .env
        log_success ".env файл обновлен"
    fi

    # Создание улучшенной конфигурации Xray с рекомендациями
    log_info "Создание оптимизированной конфигурации..."
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
            "listen": "::",
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
                    "privateKey": "$PRIVATE_KEY",
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
            "listen": "::",
            "port": 8443,
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
                    "privateKey": "$PRIVATE_KEY",
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
            "tag": "inbound-8443"
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

    # Валидация
    log_info "Проверка конфигурации..."
    if xray -test -config /usr/local/etc/xray/config.json; then
        log_success "Новая конфигурация корректна"
    else
        log_error "Ошибка в новой конфигурации!"
        xray -test -config /usr/local/etc/xray/config.json
        return 1
    fi

    # Открытие дополнительного порта в firewall
    log_info "Настройка firewall для порта 8443..."
    ufw allow 8443/tcp || true

    # Запуск сервисов
    systemctl start xray
    sleep 5

    if systemctl is-active --quiet xray; then
        log_success "Xray перезапущен с новой конфигурацией"
    else
        log_error "Не удалось запустить Xray с новой конфигурацией"
        journalctl -u xray --no-pager -n 10
        return 1
    fi

    log_success "Конфигурация успешно обновлена!"
    log_info "Доступные порты: 443, 8443"
    log_info "Используется TCP протокол для лучшей совместимости"
    log_info "Short IDs: пустая строка + $SHORT_ID"
}

# Главное меню
main_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Диагностика Xray VPN Bot ===${NC}"
        echo "1. Полная проверка системы"
        echo "2. Проверка времени и исправление"
        echo "3. Проверка firewall и исправление"
        echo "4. Проверка доступности Google"
        echo "5. Проверка сервисов"
        echo "6. Проверка портов"
        echo "7. Проверка конфигурации Xray"
        echo "8. Проверка .env файла"
        echo "9. Тест Reality соединения"
        echo "10. Показать информацию о ключах"
        echo "11. Показать логи сервисов"
        echo "12. Автоматическое исправление проблем"
        echo "13. Регенерация конфигурации с новыми ключами"
        echo "0. Выход"
        echo ""
        read -p "Выберите опцию: " choice

        case $choice in
            1)
                check_time_sync
                check_firewall
                check_google_connectivity
                check_services
                check_ports
                check_xray_config
                check_env_config
                test_reality_connection
                ;;
            2) check_time_sync ;;
            3) check_firewall ;;
            4) check_google_connectivity ;;
            5) check_services ;;
            6) check_ports ;;
            7) check_xray_config ;;
            8) check_env_config ;;
            9) test_reality_connection ;;
            10) show_keys_info ;;
            11) show_logs ;;
            12) fix_problems ;;
            13) regenerate_config ;;
            0)
                echo "До свидания!"
                exit 0
                ;;
            *)
                echo "Неверный выбор, попробуйте снова."
                ;;
        esac

        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
    log_error "Пожалуйста, запустите скрипт от имени root или с sudo"
    exit 1
fi

# Запуск главного меню
main_menu