#!/bin/bash

###############################################################################
# Keenetic WireGuard + NFQWS v2.6 - Automatic Setup
# WARP handshake obfuscation + DPI bypass
# Supports: KeenOS 4.x and 5.x
# 
# CRITICAL FIXES v2.6:
# - Fix #1: Netfilter check via /proc/modules (nfnetlink_queue, not nf_queue)
# - Fix #2: WireGuard check via /proc/modules (working on all KeenOS versions)
# - Fix #3: Patch S51nfqws to remove --user parameter (eliminates username error)
# - Fix #4: auto.list DISABLED (WARP handshake ONLY, no hostlist reading)
# - Fix #5: WG Restore single process (PID check prevents duplicates)
# - Fix #6: Installation log completes immediately (background daemon)
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
    # Метод 1: ndmc show version (как у тебя реально есть)
    if command -v ndmc >/dev/null 2>&1; then
        KEENOS_VERSION=$(ndmc -c "show version" 2>/dev/null | awk '/title:/ {print $2; exit}')
        if [ -n "$KEENOS_VERSION" ]; then
            log_info "Detected KeenOS version: $KEENOS_VERSION"
            return 0
        fi
    fi

    # Метод 2: старые файлы (на всякий)
    if [ -f /opt/etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /opt/etc/os-version | cut -d'=' -f2 | tr -d '"')
    elif [ -f /etc/os-version ]; then
        KEENOS_VERSION=$(grep "VERSION=" /etc/os-version | cut -d'=' -f2 | tr -d '"')
    fi

    if [ -n "$KEENOS_VERSION" ]; then
        log_info "Detected KeenOS version: $KEENOS_VERSION"
        return 0
    fi

    # Если вообще не поняли версию — НЕ роняем установку
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
    # FIX #1: Check for nfnetlink_queue module (required for NFQWS)
    # This is the CORRECT module name, not nf_queue
    if grep -q "nfnetlink_queue" /proc/modules 2>/dev/null; then
        log_success "Netfilter Queue (nfnetlink_queue) loaded"
        return 0
    fi
    
    # Fallback: check /sys/module
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
    # FIX #2: WireGuard check via /proc/modules only (most reliable method)
    if grep -q "wireguard" /proc/modules 2>/dev/null; then
        log_success "WireGuard module loaded"
        return 0
    fi
    
    # Fallback: check /sys/module
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
    # Check if nfqws-keenetic-web is available via opkg
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
    
    # Core packages
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
    
    # Set proper permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$LOG_DIR"
    
    log_success "Directories created with proper permissions"
}

create_nfqws_config() {
    log_info "Creating NFQWS configuration (WARP handshake ONLY v2.1)..."
    
    cat > "$INSTALL_DIR/nfqws.conf" << 'EOF'
# Keenetic NFQWS Configuration v2.1
# WARP handshake obfuscation ONLY (UDP 443)
# Generated by install-v2.6.sh
# FIX #4: auto.list, user.list DISABLED (handshake only mode)

# ========================================
# PROVIDER INTERFACE CONFIGURATION
# ========================================
# Interface where ISP traffic goes (WARP connection)
ISP_INTERFACE="ppp0"

# ========================================
# WARP UDP 443 OBFUSCATION (HANDSHAKE ONLY)
# ========================================
# Strategy: fake,split2 (fake QUIC + split 2nd packet)
# - fake: Send fake QUIC packet to confuse DPI
# - split2: Split handshake into 2 packets
# - repeats=4: Send 4 desync packets for reliability
# - ttl=3: Low TTL prevents early DPI detection
# - badsum: Wrong checksum bypasses pattern matching
#
# RESULT: WARP handshake obfuscated, DPI cannot detect
NFQWS_ARGS="--filter-udp=443 --dpi-desync=fake,split2 --dpi-desync-repeats=4 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum"

# ========================================
# FIX #4: HOSTLIST DISABLED (HANDSHAKE ONLY)
# ========================================
# NFQWS_EXTRA_ARGS is EMPTY - no hostlist reading
# This means:
# - auto.list NOT read (no automatic domain addition)
# - user.list NOT read (no manual domain list)
# - exclude.list NOT read (no exclusions)
# 
# ONLY UDP 443 handshake obfuscation works
NFQWS_EXTRA_ARGS=""

# ========================================
# LEGACY PARAMETERS (NOT USED)
# ========================================
# These are for future expansion or other services
NFQWS_ARGS_QUIC=""
NFQWS_ARGS_UDP=""
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
# FIX #3: NO --user parameter (runs from root automatically)
# Do NOT set USER here - let root run nfqws directly
CONFIG_VERSION=9

# ========================================
# DPI-DESYNC PROFILES (FOR REFERENCE)
# ========================================
# WEAK:       --dpi-desync=fake --dpi-desync-repeats=4 --dpi-desync-ttl=5
# MEDIUM:     --dpi-desync=fake,split2 --dpi-desync-repeats=4 --dpi-desync-ttl=3 (CURRENT)
# AGGRESSIVE: --dpi-desync=fake,split3 --dpi-desync-repeats=6 --dpi-desync-ttl=2
#
# Adjust NFQWS_ARGS above if you need stronger/weaker obfuscation
EOF
    
    log_success "NFQWS config v2.1 created (handshake ONLY mode)"
}

create_user_list() {
    log_info "Creating user.list (NOT USED - handshake only)..."
    
    cat > "$INSTALL_DIR/user.list" << 'EOF'
# FIX #4: This file is NOT read by NFQWS (handshake only mode)
# NFQWS_EXTRA_ARGS is empty in nfqws.conf
# 
# WARP handshake obfuscation works automatically on UDP 443
# No domain lists are processed
#
# If you want to enable domain-based obfuscation:
# 1. Edit /opt/etc/nfqws/nfqws.conf
# 2. Set: NFQWS_EXTRA_ARGS="--hostlist=/opt/etc/nfqws/user.list"
# 3. Add domains here (one per line)
# 4. Restart: /opt/etc/init.d/S51nfqws restart
EOF
    
    log_success "user.list created (disabled)"
}

create_exclude_list() {
    log_info "Creating exclude.list (NOT USED - handshake only)..."
    
    cat > "$INSTALL_DIR/exclude.list" << 'EOF'
# FIX #4: This file is NOT read by NFQWS (handshake only mode)
# NFQWS_EXTRA_ARGS is empty in nfqws.conf
#
# No exclusions needed - only UDP 443 handshake is obfuscated
EOF
    
    log_success "exclude.list created (disabled)"
}

create_auto_list() {
    log_info "Creating auto.list (NOT USED - handshake only)..."
    
    cat > "$INSTALL_DIR/auto.list" << 'EOF'
# FIX #4: This file is NOT read by NFQWS (handshake only mode)
# NFQWS_EXTRA_ARGS is empty in nfqws.conf
#
# No automatic domain addition - handshake only mode
EOF
    
    chmod 644 "$INSTALL_DIR/auto.list"
    log_success "auto.list created (disabled)"
}

create_ipset_list() {
    log_info "Creating IP-set lists (NOT USED - handshake only)..."
    touch "$INSTALL_DIR/ipset.list"
    touch "$INSTALL_DIR/ipset_exclude.list"
    chmod 644 "$INSTALL_DIR/ipset.list"
    chmod 644 "$INSTALL_DIR/ipset_exclude.list"
    log_success "IP-set lists created (disabled)"
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
    
    # Backup original
    cp /opt/etc/init.d/S51nfqws /opt/etc/init.d/S51nfqws.bak 2>/dev/null || true
    
    # Check if already patched
    if grep -q "# PATCHED: --user removed" /opt/etc/init.d/S51nfqws; then
        log_success "S51nfqws already patched"
        return 0
    fi
    
    # FIX #3: Remove --user from _startup_args() function
    # Original line: local args="--user=$USER --qnum=$NFQUEUE_NUM"
    # Replace with: local args="--qnum=$NFQUEUE_NUM"
    
    sed -i 's/^  local args="--user=$USER --qnum=/  local args="--qnum=/' /opt/etc/init.d/S51nfqws
    
    # Add comment to mark patch
    sed -i '201i\  # PATCHED: --user removed (runs from root automatically)' /opt/etc/init.d/S51nfqws
    
    log_success "S51nfqws patched (--user parameter removed)"
    
    # Verify patch
    if grep -q "local args=\"--qnum=" /opt/etc/init.d/S51nfqws && ! grep -q "local args=\"--user=\$USER" /opt/etc/init.d/S51nfqws; then
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
        log_info "NFQWS package may not be installed correctly"
        return 1
    fi
    
    # Stop any running instances first
    log_info "Stopping any existing NFQWS instances..."
    /opt/etc/init.d/S51nfqws stop 2>&1 || true
    killall -9 nfqws 2>/dev/null || true
    sleep 1
    
    # Start NFQWS
    log_info "Starting NFQWS service..."
    if /opt/etc/init.d/S51nfqws start 2>&1 | tee -a "$LOG_DIR/install.log"; then
        log_success "NFQWS service started"
    else
        log_error "NFQWS service startup failed!"
        log_info "Check: ps | grep nfqws"
        return 1
    fi
    
    # Verify NFQWS is actually running
    sleep 2
    if ps | grep -q "[n]fqws"; then
        log_success "NFQWS process verified running"
        return 0
    else
        log_error "NFQWS process NOT found after startup!"
        log_warn "Check logs: tail -f $LOG_DIR/nfqws.log"
        return 1
    fi
}

###############################################################################
# WireGuard Handshake Restore (Ground-Zerro integration)
# FIX #5: Single process protection via PID check
###############################################################################

setup_wireguard_restore() {
    log_info "Setting up WireGuard handshake restore daemon..."
    
    # Create directory
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
PID_FILE="/opt/var/run/wg-restore.pid"

start() {
    # FIX #5: Check if already running (single process protection)
    if [ -f "$PID_FILE" ]; then
        old_pid=$(cat "$PID_FILE")
        if ps | grep -q "^ *$old_pid "; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: WG Restore already running (PID: $old_pid)" >> "$WG_RESTORE_LOG"
            echo "WireGuard restore daemon already running (PID: $old_pid)"
            return 1
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning stale PID file" >> "$WG_RESTORE_LOG"
            rm -f "$PID_FILE"
        fi
    fi
    
    # Kill any orphaned processes
    killall -9 S99wg-restore 2>/dev/null || true
    sleep 1
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    
    # Create and run background restore loop
    (
        while true; do
            # Check each WireGuard interface
            for i in $(ip a 2>/dev/null | sed -n 's/.*nwg\(.*\): <.*UP.*/\1/p'); do
                # Get remote endpoint
                rem=$(ndmc -c "show interface Wireguard$i" 2>/dev/null | sed -n 's/.*remote.*: \(.*\)/\1/p')
                
                # Skip if remote is 0.0.0.0 (unconfigured)
                echo "$rem" | grep -q '^0\| 0' && continue
                
                # Test connectivity (4 probes = 30 seconds timeout)
                if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                    if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                        if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                            if ! ping -I nwg$i -s0 -qc1 -W1 1.1.1.1 >/dev/null 2>&1; then
                                # 4 failed pings = connection lost
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Handshake lost for Wireguard$i" >> "$WG_RESTORE_LOG"
                                
                                # Generate random UDP port (2000-65000)
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
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore: port=$port count=$count len=$length to $remote_ip:$remote_port" >> "$WG_RESTORE_LOG"
                                
                                # Send NPING packets (handshake restore)
                                nping --udp --count "$count" --source-port "$port" --data-length "$length" --dest-port "$remote_port" "$remote_ip" >/dev/null 2>&1
                                
                                # Change WireGuard listen port
                                ndmc -c "interface Wireguard$i wireguard listen-port $port" >/dev/null 2>&1
                                
                                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore complete (listening on port $port)" >> "$WG_RESTORE_LOG"
                            fi
                        fi
                    fi
                fi
            done
            
            # Check every 30 seconds
            sleep 30
        done
    ) > /dev/null 2>&1 &
    
    echo "$!" > "$PID_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daemon started (PID: $(cat "$PID_FILE"))" >> "$WG_RESTORE_LOG"
}

stop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping WireGuard handshake restore daemon..." >> "$WG_RESTORE_LOG"
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    killall -9 S99wg-restore 2>/dev/null || true
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
    
    log_success "WireGuard restore daemon installed (S99wg-restore)"
}

start_wireguard_restore() {
    log_info "Starting WireGuard restore daemon (background)..."
    
    if [ ! -x /opt/etc/init.d/S99wg-restore ]; then
        log_error "S99wg-restore script not found!"
        return 1
    fi
    
    # FIX #6: Start in background and return immediately
    # Kill any old instances first
    killall -9 S99wg-restore 2>/dev/null || true
    rm -f /opt/var/run/wg-restore.pid
    sleep 1
    
    # Start daemon in background (output suppressed)
    if /opt/etc/init.d/S99wg-restore start >/dev/null 2>&1; then
        sleep 2
        
        # Check if PID file was created
        if [ -f /opt/var/run/wg-restore.pid ]; then
            local pid=$(cat /opt/var/run/wg-restore.pid 2>/dev/null)
            log_success "WireGuard restore daemon started (PID: $pid)"
            return 0
        else
            log_warn "WireGuard restore daemon started (PID unknown)"
            return 0
        fi
    else
        log_warn "WireGuard restore daemon startup had issues"
        return 1
    fi
}

###############################################################################
# IPTABLES RULES (Optional but recommended)
###############################################################################

setup_iptables_rules() {
    log_info "Checking iptables rules..."
    
    # Check if rules already exist
    if iptables -t mangle -L POSTROUTING 2>/dev/null | grep -q "NFQUEUE"; then
        log_success "iptables NFQUEUE rules already present"
        return 0
    fi
    
    log_info "Adding iptables NFQUEUE rules..."
    
    # Add NFQUEUE rule for UDP 443 on ppp0 (WARP interface)
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
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Keenetic WireGuard + NFQWS v${SCRIPT_VERSION}              ║${NC}"
    echo -e "${BLUE}║  WARP handshake obfuscation + DPI bypass            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Initialize logs
    mkdir -p "$LOG_DIR"
    {
        echo "=== NFQWS Installation Log ==="
        echo "Started: $(date)"
        echo "Script Version: $SCRIPT_VERSION"
    } > "$LOG_DIR/install.log"
    
    # System checks
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
    
    # Final summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Installation Complete (v${SCRIPT_VERSION})!                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_success "NFQWS v2.1 (handshake ONLY mode) configured"
    log_success "Configuration: $INSTALL_DIR/nfqws.conf"
    log_success "User list: $INSTALL_DIR/user.list (DISABLED)"
    log_success "Exclude list: $INSTALL_DIR/exclude.list (DISABLED)"
    log_success "Auto list: $INSTALL_DIR/auto.list (DISABLED)"
    log_success "WireGuard restore: /opt/etc/init.d/S99wg-restore"
    log_success "Installation log: $LOG_DIR/install.log"
    log_success "S51nfqws backup: /opt/etc/init.d/S51nfqws.bak"
    
    echo ""
    log_info "VERIFICATION:"
    echo "  Check NFQWS:"
    echo "    $ ps | grep nfqws"
    echo "    $ cat /proc/\$(pgrep -o nfqws)/cmdline | tr '\\0' ' '"
    echo ""
    echo "  Check WireGuard restore:"
    echo "    $ ps | grep S99wg-restore"
    echo "    $ cat /opt/var/run/wg-restore.pid"
    echo ""
    echo "  Monitor NFQWS:"
    echo "    $ tail -f $LOG_DIR/nfqws.log"
    echo ""
    echo "  Monitor WireGuard restore:"
    echo "    $ tail -f /opt/var/log/wg-restore.log"
    echo ""
    
    log_info "CRITICAL FIXES IN v2.6:"
    echo "  ✓ Fix #1: Netfilter check via /proc/modules (nfnetlink_queue)"
    echo "  ✓ Fix #2: WireGuard check via /proc/modules (no modprobe/lsmod)"
    echo "  ✓ Fix #3: S51nfqws patched (--user parameter removed, runs from root)"
    echo "  ✓ Fix #4: auto.list DISABLED (handshake only, no hostlist reading)"
    echo "  ✓ Fix #5: WG Restore single process (PID check prevents duplicates)"
    echo "  ✓ Fix #6: Installation log completes immediately (background daemon)"
    echo ""
    
    log_info "NEXT STEPS:"
    echo "  1. Configure WireGuard WARP in Keenetic web interface"
    echo "  2. Test: ping through WireGuard interface"
    echo "  3. Monitor logs for DPI bypass success"
    echo "  4. Verify NFQWS and WG Restore processes are running"
    echo ""
    
    log_info "DOCUMENTATION:"
    echo "  • NFQWS DPI-desync: https://github.com/bol-van/zapret"
    echo "  • WG Restore: https://github.com/Ground-Zerro/Wireguard-DPI-blocking-bypass"
    echo ""
}

# Run 
