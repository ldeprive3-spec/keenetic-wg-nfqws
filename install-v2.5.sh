#!/bin/bash

###############################################################################
# Keenetic WireGuard + NFQWS v2.5 - Automatic Setup
# WARP handshake obfuscation + DPI bypass
# Supports: KeenOS 4.x and 5.x
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
SCRIPT_VERSION="2.5"
KEENOS_MIN_VERSION="4.0"

###############################################################################
# SYSTEM DETECTION
###############################################################################

detect_keenos_version() {
    if [ -f /opt/etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /opt/etc/os-version | cut -d'=' -f2 | tr -d '"')
    elif [ -f /etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /etc/os-version | cut -d'=' -f2 | tr -d '"')
    else
        log_error "Cannot detect KeenOS version"
        return 1
    fi
    log_info "Detected KeenOS version: $KEENOS_VERSION"
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
    # Check for nfnetlink_queue module (required for NFQWS)
    if grep -q "nfnetlink_queue" /proc/modules 2>/dev/null; then
        log_success "Netfilter Queue (nfnetlink_queue) loaded"
        return 0
    fi
    
    # Fallback: check /sys/module
    if [ -d "/sys/module/nfnetlink_queue" ]; then
        log_success "Netfilter Queue module found"
        return 0
    fi
    
    # Last resort: check nf_queue
    if grep -q "nf_queue" /proc/modules 2>/dev/null; then
        log_success "Netfilter Queue (nf_queue) loaded"
        return 0
    fi
    
    log_error "Netfilter Queue NOT found!"
    log_info "Enable: System Settings → Firewall → IPv4 settings → Netfilter"
    return 1
}

check_wireguard() {
    # Method 1: Check /proc/modules
    if grep -q "wireguard" /proc/modules 2>/dev/null; then
        log_success "WireGuard module loaded"
        return 0
    fi
    
    # Method 2: Check /sys/module
    if [ -d "/sys/module/wireguard" ]; then
        log_success "WireGuard module found"
        return 0
    fi
    
    # Method 3: Try to load module (non-blocking check)
    if modprobe wireguard 2>/dev/null; then
        log_success "WireGuard module loaded"
        return 0
    fi
    
    log_error "WireGuard module NOT loaded!"
    log_info "Enable: System Settings → Firewall → Tunneling protocols → WireGuard"
    return 1
}

check_entware_nfqws() {
    # Check if nfqws is available via opkg
    if opkg list-installed 2>/dev/null | grep -q "^nfqws"; then
        log_success "NFQWS package available in Entware"
        return 0
    fi
    
    log_warn "NFQWS package not found in Entware list"
    log_info "Will attempt to install via opkg"
    return 1
}

###############################################################################
# DEPENDENCIES INSTALLATION
###############################################################################

install_dependencies() {
    log_info "Updating package list..."
    opkg update || log_warn "opkg update had issues (continuing anyway)"
    
    log_info "Installing dependencies..."
    
    # Core packages
    local packages="nano nfqws-keenetic-web nping curl"
    
    for pkg in $packages; do
        log_info "Installing: $pkg"
        if ! opkg install "$pkg" 2>&1 | grep -q "already installed"; then
            log_success "$pkg installed"
        else
            log_success "$pkg already installed"
        fi
    done
    
    log_success "All dependencies installed"
}

###############################################################################
# DIRECTORY AND FILE CREATION
###############################################################################

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    
    log_success "Directories created"
}

create_nfqws_config() {
    log_info "Creating NFQWS configuration (WARP-only)..."
    
    cat > "$INSTALL_DIR/nfqws.conf" << 'EOF'
# Keenetic NFQWS Configuration v2.0
# WARP handshake obfuscation only
# Generated: $(date)

# Provider network interface (typically ppp0 for WARP)
ISP_INTERFACE="ppp0"

# ========================================
# WARP UDP 443 Obfuscation Strategy
# ========================================
# Fake+split2: Fakes initial QUIC packet then splits 2nd packet
# repeats=4: Send 4 desync packets
# ttl=3: Low TTL to avoid early DPI detection
# badsum: Wrong checksum to bypass pattern matching
NFQWS_ARGS="--filter-udp=443 --dpi-desync=fake,split2 --dpi-desync-repeats=4 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum"

# ========================================
# NO EXTRA STRATEGIES (WARP-ONLY MODE)
# ========================================
NFQWS_ARGS_QUIC=""
NFQWS_ARGS_UDP=""
NFQWS_EXTRA_ARGS="--hostlist=/opt/etc/nfqws/user.list"
NFQWS_ARGS_IPSET=""
NFQWS_ARGS_CUSTOM=""

# ========================================
# BASE CONFIGURATION
# ========================================
IPV6_ENABLED=0
TCP_PORTS="443"
UDP_PORTS="443"
POLICY_NAME="nfqws"
POLICY_EXCLUDE=0
LOG_LEVEL=0
NFQUEUE_NUM=200
USER="nobody"
CONFIG_VERSION=8

# ========================================
# DOCUMENTATION
# ========================================
# For detailed NFQWS arguments, see:
# https://github.com/bol-van/zapret
#
# Common DPI-desync methods:
# - fake: Send fake QUIC packet to confuse DPI
# - split2: Split handshake into 2 parts
# - split3: Split handshake into 3 parts
#
# Profile recommendations:
# WEAK:       --dpi-desync=fake --dpi-desync-repeats=4 --dpi-desync-ttl=5
# MEDIUM:     --dpi-desync=fake,split2 --dpi-desync-repeats=4 --dpi-desync-ttl=3
# AGGRESSIVE: --dpi-desync=fake,split3 --dpi-desync-repeats=6 --dpi-desync-ttl=2
EOF
    
    log_success "NFQWS config created"
}

create_user_list() {
    log_info "Creating user.list..."
    
    cat > "$INSTALL_DIR/user.list" << 'EOF'
# WARP domains (add your own if needed)
# This file stays empty by default - NFQWS uses WARP directly
# Add domains here if you need UDP 443 obfuscation for other services
EOF
    
    log_success "user.list created"
}

create_exclude_list() {
    log_info "Creating exclude.list..."
    
    cat > "$INSTALL_DIR/exclude.list" << 'EOF'
# Domains to exclude from obfuscation (leave empty for WARP-only mode)
# Examples:
# google.com
# youtube.com
EOF
    
    log_success "exclude.list created"
}

create_auto_list() {
    log_info "Creating auto.list..."
    touch "$INSTALL_DIR/auto.list"
    log_success "auto.list created"
}

create_ipset_list() {
    log_info "Creating IP-set lists..."
    touch "$INSTALL_DIR/ipset.list"
    touch "$INSTALL_DIR/ipset_exclude.list"
    log_success "IP-set lists created"
}

###############################################################################
# WireGuard Handshake Restore (Ground-Zerro integration)
###############################################################################

setup_wireguard_restore() {
    log_info "Setting up WireGuard handshake restore..."
    
    # Create WireGuard restore script directory
    mkdir -p /opt/etc/init.d
    
    cat > /opt/etc/init.d/S99wg-restore << 'EOF'
#!/bin/sh

### BEGIN INIT INFO
# Provides:          wg-restore
# Required-Start:    S51nfqws
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: WireGuard handshake restore via NPING
# Description:       Restore WireGuard connection if NFQWS obfuscation fails
### END INIT INFO

PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SCRIPT_DIR="/opt/etc/init.d"
WG_RESTORE_LOG="/opt/var/log/wg-restore.log"

start() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    
    # Create and run background restore loop
    {
        while true; do
            # Check each WireGuard interface
            for i in $(ip a 2>/dev/null | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
                # Get remote endpoint
                rem=$(ndmc -c "show interface Wireguard$i" 2>/dev/null | sed -n 's/.*remote.*: \(.*\)/\1/p')
                
                # Skip if remote is 0.0.0.0 (unconfigured)
                echo "$rem" | grep -q '^0\| 0' && continue
                
                # Test connectivity
                if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                    if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                        if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                            if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                                # 4 failed pings = connection lost
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Handshake lost for Wireguard$i" >> "$WG_RESTORE_LOG"
                                
                                # Generate random UDP port
                                port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 63000) + 2000}')
                                
                                # Ensure port is not in use
                                while netstat -nlu 2>/dev/null | grep -qw "$port"; do
                                    port=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 63000) + 2000}')
                                done
                                
                                # Random packet count (6-11)
                                count=$(hexdump -n1 -e '1/1 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 5) + 6}')
                                
                                # Random packet length (64-129 bytes)
                                length=$(hexdump -n2 -e '1/2 "%u\n"' /dev/urandom 2>/dev/null | awk '{print ($1 % 65) + 64}')
                                
                                # Extract remote IP and port
                                remote_ip=$(echo "$rem" | awk '{print $1}')
                                remote_port=$(echo "$rem" | awk '{print $2}')
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempting restore: port=$port count=$count length=$length" >> "$WG_RESTORE_LOG"
                                
                                # Send NPING packets
                                nping --udp --count "$count" --source-port "$port" --data-length "$length" --dest-port "$remote_port" "$remote_ip" >/dev/null 2>&1
                                
                                # Change WireGuard listen port
                                ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore complete for Wireguard$i" >> "$WG_RESTORE_LOG"
                            fi
                        fi
                    fi
                fi
            done
            
            # Check every 30 seconds
            sleep 30
        done
    } &
    
    echo "$$" > /opt/var/run/wg-restore.pid
}

stop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    if [ -f /opt/var/run/wg-restore.pid ]; then
        kill $(cat /opt/var/run/wg-restore.pid) 2>/dev/null || true
        rm -f /opt/var/run/wg-restore.pid
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
EOF
    
    chmod +x /opt/etc/init.d/S99wg-restore
    
    log_success "WireGuard restore daemon installed"
}

###############################################################################
# NFQWS SERVICE INTEGRATION
###############################################################################

start_nfqws() {
    log_info "Starting NFQWS service..."
    
    if [ -x /opt/etc/init.d/S51nfqws ]; then
        /opt/etc/init.d/S51nfqws restart
        log_success "NFQWS service restarted"
    else
        log_error "S51nfqws not found"
        return 1
    fi
}

###############################################################################
# MAIN INSTALLATION FLOW
###############################################################################

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Keenetic WireGuard + NFQWS Setup v${SCRIPT_VERSION}              ║${NC}"
    echo -e "${BLUE}║  WARP handshake obfuscation + DPI bypass            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # System checks
    log_info "=== SYSTEM CHECKS ==="
    detect_keenos_version || exit 1
    detect_entware || exit 1
    
    log_info "=== COMPONENT VERIFICATION ==="
    check_ipv6 || log_warn "IPv6 component not enabled"
    check_netfilter || exit 1
    check_wireguard || exit 1
    check_entware_nfqws || log_warn "NFQWS might not be available"
    
    # Installation
    log_info "=== INSTALLATION ==="
    install_dependencies
    
    log_info "=== CONFIGURATION ==="
    create_directories
    create_nfqws_config
    create_user_list
    create_exclude_list
    create_auto_list
    create_ipset_list
    
    log_info "=== WIREGUARD RESTORE ==="
    setup_wireguard_restore
    
    log_info "=== STARTING SERVICES ==="
    start_nfqws
    /opt/etc/init.d/S99wg-restore start || log_warn "WireGuard restore daemon start had issues"
    
    # Final summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Installation Complete!                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_success "NFQWS configuration: $INSTALL_DIR/nfqws.conf"
    log_success "WARP support: Enabled (UDP 443 obfuscation)"
    log_success "WireGuard restore: Enabled (fallback via NPING)"
    log_success "Logs: $LOG_DIR/nfqws.log"
    log_success "WG Restore logs: /opt/var/log/wg-restore.log"
    
    echo ""
    log_info "Next steps:"
    echo "  1. Configure WireGuard WARP in Keenetic web interface"
    echo "  2. Edit $INSTALL_DIR/user.list if needed (optional)"
    echo "  3. Monitor: tail -f $LOG_DIR/nfqws.log"
    echo "  4. Check WG restore: tail -f /opt/var/log/wg-restore.log"
    echo ""
    
    log_info "Documentation:"
    echo "  • NFQWS: https://github.com/bol-van/zapret"
    echo "  • WG Restore: https://github.com/Ground-Zerro/Wireguard-DPI-blocking-bypass"
    echo ""
}

# Run main
main "$@"
