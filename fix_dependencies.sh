#!/bin/bash

# Скрипт для исправления конфликтов зависимостей пакетов
# Решает проблемы с libappstream4, libsoup2.4-1 и другими зависимостями

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Проверка root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root (sudo)"
        exit 1
    fi
}

# Исправление конфликтов зависимостей
fix_dependencies() {
    log "Исправление конфликтов зависимостей..."
    
    # Обновление списка пакетов
    info "Обновление списка пакетов..."
    apt update
    
    # Исправление сломанных зависимостей
    info "Исправление сломанных зависимостей..."
    apt --fix-broken install -y
    
    # Очистка кэша пакетов
    info "Очистка кэша пакетов..."
    apt clean
    apt autoclean
    
    # Удаление частично установленных пакетов
    info "Проверка частично установленных пакетов..."
    dpkg --configure -a
    
    # Принудительная установка проблемных зависимостей
    info "Установка проблемных зависимостей..."
    
    # Попытка установить libsoup2.4-1 отдельно
    if ! apt install -y libsoup2.4-1; then
        warn "Не удалось установить libsoup2.4-1, пробуем альтернативный метод..."
        
        # Попытка установить из другого источника
        apt install -y --no-install-recommends libsoup2.4-1 || true
    fi
    
    # Попытка установить libappstream4
    if ! apt install -y libappstream4; then
        warn "Не удалось установить libappstream4, пробуем без рекомендаций..."
        apt install -y --no-install-recommends libappstream4 || true
    fi
    
    # Альтернативный метод через aptitude (если доступен)
    if command -v aptitude &> /dev/null; then
        info "Использование aptitude для разрешения конфликтов..."
        aptitude install -y libsoup2.4-1 libappstream4 || true
    else
        info "Установка aptitude для лучшего разрешения зависимостей..."
        apt install -y aptitude || true
        if command -v aptitude &> /dev/null; then
            aptitude install -y libsoup2.4-1 libappstream4 || true
        fi
    fi
    
    # Принудительное разрешение конфликтов
    info "Принудительное разрешение конфликтов..."
    apt -f install -y
    
    # Обновление системы
    info "Обновление системы..."
    apt upgrade -y --fix-missing || true
    
    success "Исправление зависимостей завершено"
}

# Установка минимальных зависимостей для Xray Bot
install_minimal_dependencies() {
    log "Установка минимальных зависимостей для Xray Bot..."
    
    # Основные системные пакеты
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
        "software-properties-common"
    )
    
    for package in "${essential_packages[@]}"; do
        info "Установка $package..."
        if apt install -y --no-install-recommends "$package"; then
            success "$package установлен"
        else
            warn "Не удалось установить $package, пропускаем..."
        fi
    done
    
    # Python зависимости
    info "Установка Python зависимостей..."
    python3 -m pip install --upgrade pip || true
    
    success "Минимальные зависимости установлены"
}

# Установка Xray без конфликтов
install_xray_safe() {
    log "Безопасная установка Xray..."
    
    # Проверка существующей установки
    if command -v xray &> /dev/null; then
        info "Xray уже установлен: $(xray version | head -1)"
        return 0
    fi
    
    # Загрузка и установка Xray
    info "Загрузка установочного скрипта Xray..."
    
    # Создание временной директории
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Загрузка скрипта установки
    if curl -L -o install-release.sh https://github.com/XTLS/Xray-install/raw/main/install-release.sh; then
        chmod +x install-release.sh
        
        # Установка Xray
        info "Установка Xray..."
        if bash install-release.sh install; then
            success "Xray установлен успешно"
        else
            warn "Ошибка при установке Xray, пробуем альтернативный метод..."
            
            # Альтернативная установка через прямую загрузку
            install_xray_manual
        fi
    else
        warn "Не удалось загрузить установочный скрипт, используем ручную установку..."
        install_xray_manual
    fi
    
    # Очистка временных файлов
    cd /
    rm -rf "$temp_dir"
}

# Ручная установка Xray
install_xray_manual() {
    info "Ручная установка Xray..."
    
    # Определение архитектуры
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *) arch="64" ;;
    esac
    
    # Загрузка последней версии
    local download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${arch}.zip"
    
    info "Загрузка Xray для архитектуры: $arch"
    
    if wget -O xray.zip "$download_url"; then
        unzip -o xray.zip
        
        # Установка бинарника
        install -m 755 xray /usr/local/bin/xray
        
        # Создание директорий
        mkdir -p /usr/local/etc/xray
        mkdir -p /var/log/xray
        
        # Проверка установки
        if /usr/local/bin/xray version; then
            success "Xray установлен вручную"
        else
            error "Ошибка при ручной установке Xray"
            return 1
        fi
        
        # Очистка
        rm -f xray.zip xray geoip.dat geosite.dat
    else
        error "Не удалось загрузить Xray"
        return 1
    fi
}

# Проверка и исправление системы
check_system_health() {
    log "Проверка состояния системы..."
    
    # Проверка свободного места
    local free_space=$(df / | tail -1 | awk '{print $4}')
    if [[ $free_space -lt 1048576 ]]; then  # Меньше 1GB
        warn "Мало свободного места на диске: $(df -h / | tail -1 | awk '{print $4}')"
        
        # Очистка системы
        info "Очистка системы..."
        apt autoremove -y
        apt autoclean
        journalctl --vacuum-time=7d
    fi
    
    # Проверка памяти
    local free_mem=$(free -m | grep "Mem:" | awk '{print $7}')
    if [[ $free_mem -lt 256 ]]; then
        warn "Мало свободной памяти: ${free_mem}MB"
    fi
    
    # Проверка процессов
    info "Проверка запущенных процессов..."
    if pgrep -f "apt|dpkg" > /dev/null; then
        warn "Обнаружены запущенные процессы пакетного менеджера"
        info "Ожидание завершения..."
        
        # Ожидание завершения других процессов apt
        while pgrep -f "apt|dpkg" > /dev/null; do
            sleep 5
        done
    fi
    
    success "Проверка системы завершена"
}

# Основная функция
main() {
    log "Начало исправления зависимостей системы..."
    
    check_root
    check_system_health
    fix_dependencies
    install_minimal_dependencies
    install_xray_safe
    
    success "Исправление зависимостей завершено успешно!"
    
    info "Система готова для запуска auto_setup.sh или full_diagnostic.sh"
}

# Запуск
main "$@"
