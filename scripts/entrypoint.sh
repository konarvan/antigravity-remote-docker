#!/bin/bash
# =============================================================================
# Antigravity Docker - Entrypoint Script
# =============================================================================
# This script initializes the container environment and starts all services
# =============================================================================

set -e

echo "==========================================="
echo "  Antigravity Remote Docker"
echo "  Starting container initialization..."
echo "==========================================="

# =============================================================================
# Set VNC Password
# =============================================================================
echo "Setting VNC password..."
mkdir -p ~/.vnc
echo "${VNC_PASSWORD:-antigravity}" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# =============================================================================
# Create VNC xstartup
# =============================================================================
echo "Configuring VNC xstartup..."
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Start D-Bus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Set up XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="/tmp/runtime-$USER"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Clipboard sync — after X11 is ready, with correct auth
export XAUTHORITY="$HOME/.Xauthority"

# Bridge VNC protocol clipboard <-> X11 (MUST come before autocutsel)
vncconfig -iconic &

autocutsel -fork -selection CLIPBOARD &
autocutsel -fork -selection PRIMARY &

# Start XFCE4 desktop
# Antigravity is auto-launched by supervisor after desktop is ready
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup

# =============================================================================
# Initialize Configuration
# =============================================================================
echo "Initializing configuration..."
mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml

# Apply default panel configuration if not present
if [ ! -f ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml ]; then
    echo "Applying custom panel configuration..."
    if [ -f /opt/defaults/xfce4-panel.xml ]; then
        cp /opt/defaults/xfce4-panel.xml ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
    else
        echo "Warning: Default panel config not found at /opt/defaults/xfce4-panel.xml"
    fi
fi

# =============================================================================
# Create directories
# =============================================================================
echo "Creating workspace directories..."
mkdir -p ~/workspace ~/.config ~/.antigravity

# =============================================================================
# Fix permissions
# =============================================================================
echo "Fixing permissions..."
sudo chown -R $(id -u):$(id -g) ~ 2>/dev/null || true

# =============================================================================
# Backup state.vscdb BEFORE update can wipe the chat index
# =============================================================================
VSCDB="$HOME/.config/antigravity/User/globalStorage/state.vscdb"
BACKUP_DIR="$HOME/.config/antigravity/User/globalStorage/backups"

if [ -f "$VSCDB" ]; then
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/state.vscdb.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$VSCDB" "$BACKUP_FILE" && \
        echo "[entrypoint] ✅ state.vscdb backed up → $BACKUP_FILE" || \
        echo "[entrypoint] ⚠️  state.vscdb backup failed"
    # Keep only the 10 most recent backups
    ls -t "$BACKUP_DIR"/state.vscdb.bak.* 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
else
    echo "[entrypoint] ℹ️  No state.vscdb found yet — first run or clean slate"
fi

# =============================================================================
# Check for Antigravity updates (if enabled)
# =============================================================================
if [ "${ANTIGRAVITY_AUTO_UPDATE}" = "true" ]; then
    echo "Checking for Antigravity updates..."
    /opt/scripts/update-antigravity.sh || true
fi

# =============================================================================
# Display GPU information
# =============================================================================
echo ""
echo "==========================================="
echo "  GPU Information"
echo "==========================================="
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || echo "No NVIDIA GPU detected"
echo ""

# =============================================================================
# Display connection information
# =============================================================================
echo "==========================================="
echo "  Connection Information"
echo "==========================================="
echo "  noVNC Web Access: http://localhost:${NOVNC_PORT:-6080}"
echo "  VNC Direct:       localhost:${VNC_PORT:-5901}"
echo "  Password:         (as configured)"
echo ""
echo "  Resolution will auto-adjust to browser"
echo "  Default: ${DISPLAY_WIDTH:-1920}x${DISPLAY_HEIGHT:-1080}"
echo "==========================================="
echo ""

# =============================================================================
# Execute the main command
# =============================================================================
if [ "$1" = "supervisord" ]; then
    echo "Starting Supervisor..."
    exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
else
    exec "$@"
fi
