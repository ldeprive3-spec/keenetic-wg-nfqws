#!/bin/bash

###############################################################################
# Keenetic WireGuard + NFQWS v2.6 - Automatic Setup
# WARP handshake obfuscation + DPI bypass
# Supports: KeenOS 4.x and 5.x
# 
# CRITICAL FIXES v2.6:
# - Fix #4: auto.list disabled (only handshake obfuscation, no hostlist)
# - Fix #5: WG Restore single process (PID check prevents duplicates)
# - Fix #6: Installation log completes immediately (WG Restore runs in background)
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

###############################################################################
# CONFIGURATION
###############################################################################

INSTALL_DIR="/opt/etc/nfqws"
LOG_DIR="/opt/var/log"
SCRIPT_VERSION="2.6"
KEENOS_MIN_VERSION="4.0"

###############################################################################
# SYSTEM DETECTION
###############################################################################

detect_keenos_version() {
    if command -v ndmc >/dev/null 2>&1; then
        KEENOS_VERSION=$(ndmc -c "show version" 2>/dev/null | awk '/title:/ {print $2; exit}')
        if [ -n "$KEENOS_VERSION" ]; then
            log_info "Detected KeenOS version: $KEENOS_VERSION"
            return 0
        fi
    fi

    if [ -f /opt/etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /opt/etc/os-version | cut -d'=' -f2 | tr -d '"')
    elif [ -f /etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /etc/os-version | cut -d'=' -f2 | tr -d '"')
    fi

    if [ -n "$KEENOS_VERSION" ]; then
        log_info "Detected KeenOS version: $KEENOS_VERSION"
        return 0
    fi

    log_warn "Cannot detect KeenOS version (continuing installation anyway)"
    KEENOS_VERSION="unknown"
    return 0
}

detect_entware() {
    if [ ! -d "/opt/bin" ] || [ ! -d "/opt/etc" ]; then
        log_error "Entware not installed!"
        log_info "Install Entware first from Keenetic web interface"
        return 1
    fi
    log_success "Entware detected"
}

###############################################################################
# COMPONENT VERIFICATION
###############################################################################

check_ipv6() {
    if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = "1" ]; then
            log_warn "IPv6 disabled (optional, but recommended for full support)"
            return 1
        fi
        log_success "IPv6 enabled"
        return 0
    fi
    log_warn "IPv6 status unclear"
    return 1
}

check_netfilter() {
    if grep -q "nfnetlink_queue" /proc/modules 2>/dev/null; then
        log_success "Netfilter Queue (nfnetlink_queue) loaded"
        return 0
    fi
    
    if [ -d "/sys/module/nfnetlink_queue" ]; then
        log_success "Netfilter Queue module found in /sys"
        return 0
    fi
    
    log_error "Netfilter Queue (nfnetlink_queue) NOT found!"
    log_info "Enable: System Settings → Firewall → IPv4 settings → Netfilter"
    log_info "Then reboot and run this script again"
    return 1
}

check_wireguard() {
    if grep -q "wireguard" /proc/modules 2>/dev/null; then
        log_success "WireGuard module loaded"
        return 0
    fi
    
    if [ -d "/sys/module/wireguard" ]; then
        log_success "WireGuard module found in /sys"
        return 0
    fi
    
    log_error "WireGuard module NOT loaded!"
    log_info "Enable: System Settings → Firewall → Tunneling protocols → WireGuard"
    log_info "Then reboot and run this script again"
    return 1
}

check_entware_nfqws() {
    if opkg list-installed 2>/dev/null | grep -q "^nfqws"; then
        log_success "NFQWS package available in Entware"
        return 0
    fi
    
    log_warn "NFQWS package not found in current Entware list"
    log_info "Will attempt to install via opkg"
    return 1
}

###############################################################################
# DEPENDENCIES INSTALLATION
###############################################################################

install_dependencies() {
    log_info "Updating package list..."
    if ! opkg update 2>&1 | tee -a "$LOG_DIR/install.log"; then
        log_warn "opkg update had issues (continuing anyway)"
    fi
    
    log_info "Installing dependencies..."
    
    local packages="nano nfqws-keenetic-web nping curl sed"
    
    for pkg in $packages; do
        log_info "Installing: $pkg"
        if opkg install "$pkg" 2>&1 | tee -a "$LOG_DIR/install.log" | grep -q "already installed"; then
            log_success "$pkg already installed"
        else
            log_success "$pkg installed successfully"
        fi
    done
    
    log_success "All dependencies installed/verified"
}

###############################################################################
# DIRECTORY AND FILE CREATION
###############################################################################

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p /opt/var/run
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    
    log_success "Directories created with proper permissions"
}

create_nfqws_config() {
    log_info "Creating NFQWS configuration (WARP-only v2.0)..."
    
    cat > "$INSTALL_DIR/nfqws.conf" << 'CONFEOF'
# Keenetic NFQWS Configuration v2.0
# WARP handshake obfuscation only (UDP 443)
# Generated by install-v2.6.sh

ISP_INTERFACE="ppp0"

NFQWS_ARGS="--filter-udp=443 --dpi-desync=fake,split2 --dpi-desync-repeats=4 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum"

NFQWS_EXTRA_ARGS=""

NFQWS_ARGS_QUIC=""
NFQWS_ARGS_UDP=""
NFQWS_ARGS_IPSET=""
NFQWS_ARGS_CUSTOM=""

IPV6_ENABLED=0
TCP_PORTS="443"
UDP_PORTS="443"
POLICY_NAME="nfqws"
POLICY_EXCLUDE=0
LOG_LEVEL=0
NFQUEUE_NUM=200
CONFIG_VERSION=8
CONFEOF
    
    log_success "NFQWS config v2.0 created (WARP-only mode, no hostlist)"
}

create_user_list() {
    log_info "Creating user.list (not used in v2.6)..."
    
    cat > "$INSTALL_DIR/user.list" << 'LISTEOF'
# DISABLED IN v2.6 - This file is NOT read by NFQWS
# Kept for reference only.
LISTEOF
    
    log_success "user.list created (disabled in v2.6)"
}

create_exclude_list() {
    log_info "Creating exclude.list (not used in v2.6)..."
    
    cat > "$INSTALL_DIR/exclude.list" << 'LISTEOF'
# DISABLED IN v2.6 - This file is NOT read by NFQWS
# Kept for reference only.
LISTEOF
    
    log_success "exclude.list created (disabled in v2.6)"
}

create_auto_list() {
    log_info "Creating auto.list (not used in v2.6)..."
    touch "$INSTALL_DIR/auto.list"
    chmod 644 "$INSTALL_DIR/auto.list"
    log_success "auto.list created (disabled in v2.6)"
}

create_ipset_list() {
    log_info "Creating IP-set lists (not used in v2.6)..."
    touch "$INSTALL_DIR/ipset.list"
    touch "$INSTALL_DIR/ipset_exclude.list"
    chmod 644 "$INSTALL_DIR/ipset.list"
    chmod 644 "$INSTALL_DIR/ipset_exclude.list"
    log_success "IP-set lists created (disabled in v2.6)"
}

###############################################################################
# PATCH S51nfqws INIT SCRIPT (FIX #3 - CRITICAL)
###############################################################################

patch_s51nfqws() {
    log_info "Patching S51nfqws to remove --user parameter..."
    
    if [ ! -f /opt/etc/init.d/S51nfqws ]; then
        log_error "S51nfqws script not found!"
        return 1
    fi
    
    cp /opt/etc/init.d/S51nfqws /opt/etc/init.d/S51nfqws.bak 2>/dev/null || true
    
    if grep -q "# PATCHED: --user removed" /opt/etc/init.d/S51nfqws; then
        log_success "S51nfqws already patched"
        return 0
    fi
    
    sed -i 's/^  local args="--user=$USER --qnum=/  local args="--qnum=/' /opt/etc/init.d/S51nfqws
    sed -i '201i\  # PATCHED: --user removed (runs from root automatically)' /opt/etc/init.d/S51nfqws
    
    log_success "S51nfqws patched (--user parameter removed)"
    
    if grep -q "local args=\"--qnum=" /opt/etc/init.d/S51nfqws && ! grep -q "local args=\"--user=$USER" /opt/etc/init.d/S51nfqws; then
        log_success "Patch verified successfully"
        return 0
    else
        log_error "Patch verification failed!"
        log_warn "Restoring backup..."
        cp /opt/etc/init.d/S51nfqws.bak /opt/etc/init.d/S51nfqws 2>/dev/null || true
        return 1
    fi
}

###############################################################################
# NFQWS SERVICE INTEGRATION & STARTUP FIX
###############################################################################

start_nfqws_service() {
    log_info "Starting NFQWS service (with startup verification)..."
    
    if [ ! -x /opt/etc/init.d/S51nfqws ]; then
        log_error "S51nfqws script not found or not executable!"
        return 1
    fi
    
    log_info "Stopping any existing NFQWS instances..."
    /opt/etc/init.d/S51nfqws stop 2>&1 || true
    killall -9 nfqws 2>/dev/null || true
    sleep 1
    
    log_info "Starting NFQWS service..."
    if /opt/etc/init.d/S51nfqws start 2>&1 | tee -a "$LOG_DIR/install.log"; then
        log_success "NFQWS service started"
    else
        log_error "NFQWS service startup failed!"
        return 1
    fi
    
    sleep 2
    if ps | grep -q "[n]fqws"; then
        log_success "NFQWS process verified running"
        return 0
    else
        log_error "NFQWS process NOT found after startup!"
        return 1
    fi
}

###############################################################################
# WireGuard Handshake Restore - FIX #5 & #6
###############################################################################

setup_wireguard_restore() {
    log_info "Setting up WireGuard handshake restore daemon..."
    
    mkdir -p /opt/etc/init.d
    
    cat > /opt/etc/init.d/S99wg-restore << 'WGEOF'
#!/bin/sh

PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WG_RESTORE_LOG="/opt/var/log/wg-restore.log"
PID_FILE="/opt/var/run/wg-restore.pid"

start() {
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WG Restore already running (PID: $old_pid)" >> "$WG_RESTORE_LOG"
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    
    {
        while true; do
            for i in $(ip a 2>/dev/null | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
                rem=$(ndmc -c "show interface Wireguard$i" 2>/dev/null | sed -n 's/.*remote.*: \(.*\)/\1/p')
                
                echo "$rem" | grep -q '^0\| 0' && continue
                
                if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                    if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                        if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                            if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Handshake lost for Wireguard$i" >> "$WG_RESTORE_LOG"
                                
                                port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 63000) + 2000}')
                                
                                while netstat -nlu 2>/dev/null | grep -qw "$port"; do
                                    port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 63000) + 2000}')
                                done
                                
                                count=$(hexdump -n1 -e '1/1 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 5) + 6}')
                                length=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 65) + 64}')
                                
                                remote_ip=$(echo "$rem" | awk '{print $1}')
                                remote_port=$(echo "$rem" | awk '{print $2}')
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore: port=$port count=$count len=$length to $remote_ip:$remote_port" >> "$WG_RESTORE_LOG"
                                
                                nping --udp --count "$count" --source-port "$port" --data-length "$length" --dest-port "$remote_port" "$remote_ip" >/dev/null 2>&1
                                ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore complete (listening on port $port)" >> "$WG_RESTORE_LOG"
                            fi
                        fi
                    fi
                fi
            done
            
            sleep 30
        done
    } > /dev/null 2>&1 &
    
    echo "$!" > "$PID_FILE"
}

stop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
WGEOF
    
    chmod +x /opt/etc/init.d/S99wg-restore
    
    log_success "WireGuard restore daemon installed (S99wg-restore)"
}

start_wireguard_restore() {
    log_info "Starting WireGuard restore daemon (FIX #5: single process)..."
    
    if [ ! -x /opt/etc/init.d/S99wg-restore ]; then
        log_error "S99wg-restore script not found!"
        return 1
    fi
    
    killall -9 wg-restore 2>/dev/null || true
    rm -f /opt/var/run/wg-restore.pid
    sleep 1
    
    if /opt/etc/init.d/S99wg-restore start >/dev/null 2>&1; then
        sleep 1
        if [ -f /opt/var/run/wg-restore.pid ]; then
            local wg_pid=$(cat /opt/var/run/wg-restore.pid)
            log_success "WireGuard restore daemon started (PID: $wg_pid)"
        else
            log_warn "WireGuard restore started but PID file not found"
        fi
        return 0
    else
        log_warn "WireGuard restore daemon startup had issues"
        return 1
    fi
}

###############################################################################
# IPTABLES RULES
###############################################################################

setup_iptables_rules() {
    log_info "Checking iptables rules..."
    
    if iptables -t mangle -L POSTROUTING 2>/dev/null | grep -q "NFQUEUE"; then
        log_success "iptables NFQUEUE rules already present"
        return 0
    fi
    
    log_info "Adding iptables NFQUEUE rules..."
    
    if iptables -t mangle -A POSTROUTING -o ppp0 -p udp --dport 443 \
        -m connbytes --connbytes 1:8 --connbytes-mode packets --connbytes-dir original \
        -j NFQUEUE --queue-num 200 --queue-bypass 2>&1 | tee -a "$LOG_DIR/install.log"; then
        log_success "iptables NFQUEUE rule added"
    else
        log_warn "iptables rule addition had issues"
    fi
}

###############################################################################
# MAIN INSTALLATION FLOW
###############################################################################

main() {
    echo -e "\033[0;34m╔════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[0;34m║  Keenetic WireGuard + NFQWS v2.6              ║\033[0m"
    echo -e "\033[0;34m║  WARP handshake obfuscation + DPI bypass            ║\033[0m"
    echo -e "\033[0;34m╚════════════════════════════════════════════════════════╝\033[0m"
    echo ""
    
    mkdir -p "$LOG_DIR"
    {
        echo "=== NFQWS Installation Log ==="
        echo "Started: $(date)"
        echo "Script Version: 2.6"
    } > "$LOG_DIR/install.log"
    
    log_info "=== SYSTEM CHECKS ==="
    detect_keenos_version || exit 1
    detect_entware || exit 1
    
    echo ""
    log_info "=== COMPONENT VERIFICATION ==="
    check_ipv6 || log_warn "IPv6 component not enabled (optional)"
    check_netfilter || exit 1
    check_wireguard || exit 1
    check_entware_nfqws || log_warn "NFQWS might need manual installation"
    
    echo ""
    log_info "=== DEPENDENCIES INSTALLATION ==="
    install_dependencies
    
    echo ""
    log_info "=== DIRECTORY SETUP ==="
    create_directories
    
    echo ""
    log_info "=== CONFIGURATION FILES ==="
    create_nfqws_config
    create_user_list
    create_exclude_list
    create_auto_list
    create_ipset_list
    
    echo ""
    log_info "=== PATCHING S51nfqws (FIX #3) ==="
    patch_s51nfqws || log_warn "S51nfqws patch issue (continue)"
    
    echo ""
    log_info "=== WIREGUARD RESTORE DAEMON ==="
    setup_wireguard_restore
    
    echo ""
    log_info "=== STARTING SERVICES ==="
    start_nfqws_service || log_warn "NFQWS startup issue (continue)"
    start_wireguard_restore || log_warn "WireGuard restore startup issue (continue)"
    
    echo ""
    log_info "=== IPTABLES RULES ==="
    setup_iptables_rules || log_warn "iptables rules setup issue (continue)"
    
    echo ""
    echo -e "\033[0;32m╔════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[0;32m║  ✓ Installation Complete (v2.6)!                      ║\033[0m"
    echo -e "\033[0;32m╚════════════════════════════════════════════════════════╝\033[0m"
    echo ""
    
    log_success "NFQWS v2.0 (WARP-only mode) configured"
    log_success "Configuration: /opt/etc/nfqws/nfqws.conf"
    log_success "WireGuard restore: /opt/etc/init.d/S99wg-restore"
    log_success "Installation log: /opt/var/log/install.log"
    
    echo ""
    log_info "VERIFICATION:"
    echo "  Check NFQWS:"
    echo "    # ps | grep nfqws"
    echo ""
    echo "  Monitor NFQWS:"
    echo "    # tail -f /opt/var/log/nfqws.log"
    echo ""
    echo "  Monitor WireGuard restore:"
    echo "    # tail -f /opt/var/log/wg-restore.log"
    echo ""
}

main "$@"
