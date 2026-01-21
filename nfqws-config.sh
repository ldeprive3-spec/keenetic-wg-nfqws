#!/bin/sh

# ============================================================================
# Keenetic NFQWS Configuration Manager
# ============================================================================
# Управление параметрами обфускации NFQWS для WireGuard handshake
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_FILE="/opt/etc/nfqws/nfqws.conf"
LOG_FILE="/opt/var/log/nfqws.log"

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

check_nfqws() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Конфиг NFQWS не найден: $CONFIG_FILE"
        log_info "Сначала запустите: install.sh"
        exit 1
    fi
}

show_menu() {
    echo ""
    echo "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${NC}           NFQWS Configuration Manager v2.3                    ${BLUE}║${NC}"
    echo "${BLUE}║${NC}          WireGuard Handshake Obfuscation                     ${BLUE}║${NC}"
    echo "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "${GREEN}1.${NC} Просмотр текущей конфигурации"
    echo "${GREEN}2.${NC} Просмотр логов NFQWS"
    echo "${GREEN}3.${NC} Статус NFQWS и WireGuard"
    echo ""
    echo "${GREEN}4.${NC} Слабая обфускация (быстрый интернет)"
    echo "${GREEN}5.${NC} Средняя обфускация (рекомендуется)"
    echo "${GREEN}6.${NC} Агрессивная обфускация (максимальная защита)"
    echo ""
    echo "${GREEN}7.${NC} Ручное редактирование конфига"
    echo "${GREEN}8.${NC} Перезагрузка NFQWS"
    echo ""
    echo "${GREEN}0.${NC} Выход"
    echo ""
}

show_config() {
    log_info "Текущая конфигурация NFQWS:"
    echo ""
    grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | sed 's/^/  /'
    echo ""
}

show_logs() {
    log_info "Последние 30 строк логов NFQWS:"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        tail -30 "$LOG_FILE" | sed 's/^/  /'
    else
        log_warn "Логи еще не созданы (NFQWS не запускался с логированием)"
    fi
    echo ""
}

show_status() {
    echo ""
    log_info "Статус NFQWS:"
    echo ""

    # Проверка процесса
    if ps | grep -v grep | grep -q nfqws; then
        log_success "NFQWS работает"
        echo ""
        echo "  Процесс NFQWS:"
        ps | grep nfqws | grep -v grep | sed 's/^/    /'
    else
        log_warn "NFQWS не запущен"
    fi

    echo ""

    # Проверка WireGuard интерфейса
    if command -v show &> /dev/null; then
        echo "  WireGuard интерфейсы:"
        WG_IF=$(show interface | grep -i wireguard | head -1)
        if [ -n "$WG_IF" ]; then
            show interface | grep -i wireguard | sed 's/^/    /'
        else
            echo "    (нет активных WireGuard интерфейсов)"
        fi
    fi

    echo ""

    # Проверка статуса сервиса
    if /opt/etc/init.d/S51nfqws status &>/dev/null; then
        log_success "Сервис S51nfqws работает"
    else
        log_warn "Сервис S51nfqws выключен"
    fi

    echo ""
}

apply_weak_config() {
    log_info "Применение конфигурации для слабой обфускации..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# ============================================================================
# NFQWS Configuration - Weak Obfuscation (Fast Internet)
# ============================================================================
# Для условий с слабой блокировкой DPI

--dpi-desync=fake,split
--dpi-desync-repeats=2
--dpi-desync-ttl=5
--dpi-desync-fooling=badsum

EOF

    log_success "Конфиг для слабой обфускации применен"
    echo ""
    echo "  ${YELLOW}Параметры:${NC}"
    echo "    - Способ: fake, split (минимальная фрагментация)"
    echo "    - Повторения: 2 (быстро, минимальная нагрузка)"
    echo "    - TTL: 5"
    echo ""
    restart_nfqws
}

apply_medium_config() {
    log_info "Применение конфигурации для средней обфускации..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# ============================================================================
# NFQWS Configuration - Medium Obfuscation (Recommended)
# ============================================================================
# Для большинства случаев - оптимальный баланс

--dpi-desync=fake,split2
--dpi-desync-repeats=4
--dpi-desync-ttl=3
--dpi-desync-fooling=badsum

EOF

    log_success "Конфиг для средней обфускации применен"
    echo ""
    echo "  ${YELLOW}Параметры:${NC}"
    echo "    - Способ: fake, split2 (двойная фрагментация)"
    echo "    - Повторения: 4 (оптимальный баланс)"
    echo "    - TTL: 3"
    echo ""
    restart_nfqws
}

apply_aggressive_config() {
    log_info "Применение конфигурации для агрессивной обфускации..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# ============================================================================
# NFQWS Configuration - Aggressive Obfuscation (Maximum Protection)
# ============================================================================
# Для агрессивной блокировки DPI провайдера

--dpi-desync=fake,split2,disorder
--dpi-desync-repeats=8
--dpi-desync-ttl=5
--dpi-desync-fooling=badsum

EOF

    log_success "Конфиг для агрессивной обфускации применен"
    echo ""
    echo "  ${YELLOW}Параметры:${NC}"
    echo "    - Способ: fake, split2, disorder (максимальная обфускация)"
    echo "    - Повторения: 8 (максимально надежно)"
    echo "    - TTL: 5"
    echo ""
    echo "  ${YELLOW}Внимание: может снизить скорость интернета!${NC}"
    echo ""
    restart_nfqws
}

edit_config() {
    log_info "Редактирование конфига NFQWS"
    echo ""
    echo "  Откроется редактор nano. После редактирования:"
    echo "  - Сохраните: Ctrl+X → Y → Enter"
    echo "  - NFQWS перезагружается автоматически"
    echo ""

    read -p "Открыть редактор? (y/n): " -r
    if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
        nano "$CONFIG_FILE"
        log_info "Перезагружаю NFQWS..."
        restart_nfqws
    else
        log_warn "Редактирование отменено"
    fi
}

restart_nfqws() {
    log_info "Перезагружаю NFQWS..."
    
    if /opt/etc/init.d/S51nfqws restart; then
        sleep 2
        log_success "NFQWS перезагружен"
        
        if ps | grep -v grep | grep -q nfqws; then
            log_success "NFQWS работает"
        else
            log_error "NFQWS не запустился после перезагрузки"
            log_warn "Попробуйте перезагрузить маршрутизатор: reboot"
        fi
    else
        log_error "Ошибка при перезагрузке NFQWS"
    fi
}

# ============================================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# ============================================================================

interactive_mode() {
    while true; do
        show_menu
        read -p "Выберите опцию (0-8): " -r choice

        case $choice in
            1)
                show_config
                ;;
            2)
                show_logs
                ;;
            3)
                show_status
                ;;
            4)
                apply_weak_config
                ;;
            5)
                apply_medium_config
                ;;
            6)
                apply_aggressive_config
                ;;
            7)
                edit_config
                ;;
            8)
                restart_nfqws
                ;;
            0)
                log_info "Выход"
                exit 0
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac

        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# ============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================================================

main() {
    check_root
    check_nfqws

    if [ $# -eq 0 ]; then
        interactive_mode
    else
        case "$1" in
            status)
                show_status
                ;;
            config)
                show_config
                ;;
            logs)
                show_logs
                ;;
            weak)
                apply_weak_config
                ;;
            medium)
                apply_medium_config
                ;;
            aggressive)
                apply_aggressive_config
                ;;
            restart)
                restart_nfqws
                ;;
            edit)
                edit_config
                ;;
            *)
                log_error "Неизвестная команда: $1"
                echo ""
                echo "Использование:"
                echo "  $0                - интерактивное меню"
                echo "  $0 status         - показать статус"
                echo "  $0 config         - показать конфиг"
                echo "  $0 logs           - показать логи"
                echo "  $0 weak           - применить слабую обфускацию"
                echo "  $0 medium         - применить среднюю обфускацию"
                echo "  $0 aggressive     - применить агрессивную обфускацию"
                echo "  $0 restart        - перезагрузить NFQWS"
                echo "  $0 edit           - отредактировать конфиг"
                exit 1
                ;;
        esac
    fi
}

main "$@"
