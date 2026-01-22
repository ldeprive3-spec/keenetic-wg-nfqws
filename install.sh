#!/bin/sh

# ============================================================================
# Keenetic WireGuard + NFQWS Installer
# ============================================================================
# Полностью автоматическая установка NFQWS для обфускации WireGuard
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# ФУНКЦИИ
# ============================================================================

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo "${RED}[✗]${NC} $1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Необходимо запустить от пользователя root (admin)"
        exit 1
    fi
}

check_requirements() {
    log_info "Проверка требуемых компонентов..."

    # Проверка IPv6
    if ! ip -6 addr show | grep -q "inet6"; then
        log_error "IPv6 не установлен. Установите в Управление → Параметры системы → IPv6"
        exit 1
    fi
    log_success "IPv6 установлен"

    # Проверка Netfilter
    if ! lsmod | grep -q "nfnetlink_queue"; then
        log_error "Netfilter модули не установлены. Установите в Управление → Параметры системы"
        exit 1
    fi
    log_success "Netfilter модули установлены"

    # Проверка WireGuard
    if ! modprobe -n wireguard &>/dev/null; then
        log_error "WireGuard VPN не установлен. Установите в Управление → Параметры системы"
        exit 1
    fi
    log_success "WireGuard VPN установлен"

    # Проверка Entware
    if ! command -v opkg &> /dev/null; then
        log_error "Entware не установлен. Установите в Управление → Параметры системы"
        exit 1
    fi
    log_success "Entware установлен"

    # Проверка памяти
    AVAILABLE_MEMORY=$(free -m | awk 'NR==2{print $7}')
    if [ "$AVAILABLE_MEMORY" -lt 256 ]; then
        log_warn "Доступная память: ${AVAILABLE_MEMORY}MB (рекомендуется 512MB+)"
    else
        log_success "Доступная память: ${AVAILABLE_MEMORY}MB"
    fi
}

install_nfqws() {
    log_info "Установка NFQWS..."

    # Обновление репозиториев
    log_info "Обновление пакетных репозиториев..."
    opkg update

    # Установка требуемых зависимостей
    log_info "Установка зависимостей..."
    opkg install ca-certificates wget-ssl

    # Добавление репозитория NFQWS
    log_info "Добавление репозитория NFQWS..."
    mkdir -p /opt/etc/opkg
    echo "src/gz nfqws-keenetic https://anonym-tsk.github.io/nfqws-keenetic/all" > /opt/etc/opkg/nfqws-keenetic.conf

    # Повторное обновление для нового репозитория
    opkg update

    # Установка NFQWS
    log_info "Установка пакета nfqws-keenetic..."
    if opkg install nfqws-keenetic; then
        log_success "NFQWS успешно установлен"
    else
        log_error "Ошибка при установке NFQWS"
        exit 1
    fi
}

configure_nfqws() {
    log_info "Конфигурация NFQWS (автоматическая)..."

    # Создание каталогов
    mkdir -p /opt/etc/nfqws
    mkdir -p /opt/var/log

    # Создание конфига с рекомендуемыми параметрами (средние параметры)
    cat > /opt/etc/nfqws/nfqws.conf << 'EOF'
# ============================================================================
# NFQWS Configuration - Medium Obfuscation (Recommended)
# ============================================================================

--dpi-desync=fake,split2
--dpi-desync-repeats=4
--dpi-desync-ttl=3
--dpi-desync-fooling=badsum
EOF

    log_success "Конфиг NFQWS создан с рекомендуемыми параметрами"
    chmod 644 /opt/etc/nfqws/nfqws.conf
}

setup_autostart() {
    log_info "Настройка автозагрузки NFQWS..."

    if [ -f /opt/etc/init.d/S51nfqws ]; then
        log_success "Скрипт автозагрузки найден"
        chmod 755 /opt/etc/init.d/S51nfqws
    else
        log_warn "Скрипт автозагрузки не найден, NFQWS нужно включать вручную"
    fi
}

start_nfqws() {
    log_info "Запуск NFQWS..."

    if /opt/etc/init.d/S51nfqws start; then
        sleep 2
        log_success "NFQWS запущен"

        # Проверка статуса
        if ps | grep -v grep | grep -q nfqws; then
            log_success "NFQWS работает (процесс найден)"
        else
            log_error "NFQWS не запустился"
        fi
    else
        log_error "Ошибка при запуске NFQWS"
        exit 1
    fi
}

print_next_steps() {
    echo ""
    echo "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${NC}                   УСТАНОВКА ЗАВЕРШЕНА ✓                      ${BLUE}║${NC}"
    echo "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "${GREEN}✓ NFQWS установлен и работает${NC}"
    echo ""
    echo "${GREEN}Теперь нужно:${NC}"
    echo ""
    echo "  ${YELLOW}1. Создайте WireGuard конфиг WARP:${NC}"
    echo "     - Откройте: https://warpgen.net"
    echo "     - Выберите: WireGuard или AmneziaVPN"
    echo "     - Нажмите: Generate"
    echo "     - Скопируйте конфиг"
    echo ""
    echo "  ${YELLOW}2. Загрузите конфиг в Keenetic:${NC}"
    echo "     ssh admin@192.168.1.1"
    echo "     nano /opt/etc/wireguard/warp.conf"
    echo "     # Вставьте конфиг (Ctrl+X → Y → Enter)"
    echo ""
    echo "  ${YELLOW}3. Включите WireGuard в веб-интерфейсе:${NC}"
    echo "     Интернет → Другие подключения → WireGuard"
    echo "     → Переведите в состояние: Включено"
    echo ""
    echo "  ${YELLOW}4. Проверьте подключение:${NC}"
    echo "     ssh admin@192.168.1.1"
    echo "     show interface Wireguard0"
    echo "     # Должен быть Up с трафиком RX/TX"
    echo ""
    echo "${GREEN}Управление конфигурацией:${NC}"
    echo ""
    echo "  # Интерактивное меню"
    echo "  nfqws-config.sh"
    echo ""
    echo "  # Или команды напрямую:"
    echo "  nfqws-config.sh weak         # Слабая обфускация"
    echo "  nfqws-config.sh medium       # Средняя обфускация (текущая)"
    echo "  nfqws-config.sh aggressive   # Агрессивная обфускация"
    echo "  nfqws-config.sh status       # Статус NFQWS"
    echo "  nfqws-config.sh logs         # Логи"
    echo ""
    echo "${GREEN}Проверка работы:${NC}"
    echo ""
    echo "  https://whatismyipaddress.com     (IP должен быть Cloudflare)"
    echo "  https://dnsleaktest.com           (DNS должен быть Cloudflare)"
    echo "  https://speedtest.net             (скорость близко к норме)"
    echo ""
}

# ============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================================================

main() {
    echo "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${NC}  Keenetic WireGuard + NFQWS DPI Bypass - Автоматическая     ${BLUE}║${NC}"
    echo "${BLUE}║${NC}  установка                             v2.3 (2026-01-21)  ${BLUE}║${NC}"
    echo "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    check_requirements
    install_nfqws
    configure_nfqws
    setup_autostart
    start_nfqws
    print_next_steps
}

# ============================================================================
# ЗАПУСК
# ============================================================================

main "$@"
