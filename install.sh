#!/bin/sh

# ============================================================================
# Keenetic WireGuard + NFQWS Installer
# ============================================================================
# Установка NFQWS для обфускации WireGuard handshake пакетов
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
    if ! lsmod | grep -q "nf_queue"; then
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
    log_info "Конфигурация NFQWS..."

    # Создание каталога конфигурации
    mkdir -p /opt/etc/nfqws
    mkdir -p /opt/var/log

    # Создание конфига для WireGuard handshake обфускации
    cat > /opt/etc/nfqws/nfqws.conf << 'EOF'
# ============================================================================
# NFQWS - WireGuard Handshake Obfuscation Configuration
# ============================================================================
# Обфускация WireGuard handshake пакетов для обхода DPI блокировок
# Работает с конфигами WARP от warpgen.net

# Режимы обфускации:
# - fake: отправка поддельного пакета
# - split2: разделение пакета на 2 части
# - split3: разделение на 3 части
# - disorder: беспорядок пакетов
--dpi-desync=fake,split2

# Количество повторений обфускации (1-8)
# 4 = оптимальный баланс между надежностью и скоростью
--dpi-desync-repeats=4

# TTL для поддельных пакетов
# Поддельные пакеты не должны доходить до целевого сервера
--dpi-desync-ttl=3

# Маскировка:
# - badsum: неправильная контрольная сумма
# - badseq: неправильный номер последовательности
--dpi-desync-fooling=badsum

# ВАЖНО: Раскомментируйте для обфускации только WireGuard портов
# Порт по умолчанию в WARP конфигах - 51820 (может отличаться)
# --dpi-desync-udp=51820

EOF

    log_success "Конфиг NFQWS создан: /opt/etc/nfqws/nfqws.conf"
    chmod 644 /opt/etc/nfqws/nfqws.conf
}

setup_autostart() {
    log_info "Настройка автозагрузки NFQWS..."

    # NFQWS уже должен быть в /opt/etc/init.d (установлено через opkg)
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
            log_info "Проверьте логи: tail -20 /opt/var/log/nfqws.log"
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
    echo "${GREEN}1. Следующие шаги:${NC}"
    echo ""
    echo "   ${YELLOW}a) Создайте WireGuard конфиг WARP:${NC}"
    echo "      - Откройте: https://warpgen.net"
    echo "      - Выберите: AmneziaVPN (для AWG 1.5) или WireGuard"
    echo "      - Нажмите: Generate"
    echo "      - Скопируйте конфиг"
    echo ""
    echo "   ${YELLOW}b) Загрузите конфиг в Keenetic:${NC}"
    echo "      ssh admin@192.168.1.1"
    echo "      nano /opt/etc/wireguard/warp.conf"
    echo "      # Вставьте конфиг и сохраните"
    echo ""
    echo "   ${YELLOW}c) Включите WireGuard:${NC}"
    echo "      - Интернет → Другие подключения → WireGuard"
    echo "      - Переведите в состояние: Включено"
    echo "      - Через 3-5 сек должна появиться зелёная точка"
    echo ""
    echo "   ${YELLOW}d) Проверьте подключение:${NC}"
    echo "      ssh admin@192.168.1.1"
    echo "      show interface Wireguard0"
    echo "      # Должен быть Up с увеличивающимся трафиком RX/TX"
    echo ""
    echo "${GREEN}2. Управление NFQWS:${NC}"
    echo ""
    echo "   # Статус"
    echo "   /opt/etc/init.d/S51nfqws status"
    echo ""
    echo "   # Управление"
    echo "   /opt/etc/init.d/S51nfqws start|stop|restart"
    echo ""
    echo "   # Логи (для отладки)"
    echo "   tail -f /opt/var/log/nfqws.log"
    echo ""
    echo "   # Текущие параметры"
    echo "   cat /opt/etc/nfqws/nfqws.conf"
    echo ""
    echo "${GREEN}3. Проверка работы:${NC}"
    echo ""
    echo "   # На маршрутизаторе:"
    echo "   show interface Wireguard0      # Должен быть статус Up"
    echo "   ps | grep nfqws                # Должен быть процесс NFQWS"
    echo ""
    echo "   # На любом устройстве в сети:"
    echo "   - https://whatismyipaddress.com (должен быть Cloudflare IP)"
    echo "   - https://dnsleaktest.com (должен быть Cloudflare DNS)"
    echo "   - https://speedtest.net (скорость должна быть близко к норме)"
    echo ""
    echo "${YELLOW}4. Если WireGuard отключается:${NC}"
    echo ""
    echo "   # Проверьте что NFQWS работает:"
    echo "   ps | grep nfqws"
    echo ""
    echo "   # Увеличьте параметры обфускации:"
    echo "   nano /opt/etc/nfqws/nfqws.conf"
    echo "   # Измените repeats с 4 на 8 и добавьте disorder"
    echo "   /opt/etc/init.d/S51nfqws restart"
    echo ""
    echo "   # Получите новый конфиг WARP:"
    echo "   # warpgen.net регулярно меняет endpoints"
    echo ""
}

# ============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================================================

main() {
    echo "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${NC}    Keenetic WireGuard + NFQWS DPI Bypass Installer            ${BLUE}║${NC}"
    echo "${BLUE}║${NC}                       v2.3 (2026-01-21)                      ${BLUE}║${NC}"
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
