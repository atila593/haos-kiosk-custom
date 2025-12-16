#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.2-chromium-clean-display"

# --- CORRECTIF CRITIQUE 1 : Silence total du noyau ---
# Empêche les messages "Bluetooth: hci0: unexpected event" de s'afficher sur l'écran physique
dmesg -D 

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"
ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant') HAOS=$(echo "$ha_info" | jq -r '.hassos') MACHINE=$(echo "$ha_info" | jq -r '.machine') ARCH=$(echo "$ha_info" | jq -r '.arch')"

#### Clean up on exit:
TTY0_DELETED=""
ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"
cleanup() {
    local exit_code=$?
    if [ "$SAVE_ONSCREEN_CONFIG" = true ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE" 2>/dev/null || true
    fi
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Get config variables from HA add-on & set environment variables
load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"
    local VALUE

    if declare -p "$VAR_NAME" >/dev/null 2>&1; then
        VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    else
        bashio::log.warning "Unknown config key: ${VAR_NAME,,}"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        bashio::log.warning "Config key '${VAR_NAME,,}' unset, setting to default: '$DEFAULT'"
        VALUE="$DEFAULT"
    fi

    printf -v "$VAR_NAME" '%s' "$VALUE"
    eval "export $VAR_NAME"

    if [ -z "$MASK" ]; then
        bashio::log.info "$VAR_NAME=$VALUE"
    else
        bashio::log.info "$VAR_NAME=XXXXXX"
    fi
}

load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var LOGIN_DELAY 1.0
load_config_var ZOOM_LEVEL 100
load_config_var BROWSER_REFRESH 600
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var DARK_MODE true
load_config_var HA_SIDEBAR "none"
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT us
load_config_var ONSCREEN_KEYBOARD false
load_config_var SAVE_ONSCREEN_CONFIG true
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var REST_PORT 8080
load_config_var REST_BEARER_TOKEN "" 1
load_config_var ALLOW_USER_COMMANDS false
[ "$ALLOW_USER_COMMANDS" = "true" ] && bashio::log.warning "WARNING: 'allow_user_commands' set to 'true'"
load_config_var DEBUG_MODE false

if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.warning "Warning: HA_USERNAME and HA_PASSWORD not set, auto-login disabled"
    AUTO_LOGIN=false
else
    AUTO_LOGIN=true
fi

################################################################################
#### Start Dbus
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
fi
bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_ADDRESS
echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile"

#### CRITICAL HACK: Delete /dev/tty0 temporarily so X can start
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Attempting to remount /dev as 'rw' so we can (temporarily) delete /dev/tty0..."
    mount -o remount,rw /dev || true
    if ! rm -f /dev/tty0 ; then
        bashio::log.warning "WARNING: Failed to delete /dev/tty0. Continuing anyway."
    fi
    TTY0_DELETED=1
fi

#### Start udev
bashio::log.info "Starting 'udevd'..."
udevd --daemon || true
udevadm trigger || true
udevadm settle --timeout=10

#### Start Xorg
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "fbdev"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Card0"
EndSection
EOF

bashio::log.info "Starting X..."
NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"
Xorg $NOCURSOR </dev/null &
sleep 5
export DISPLAY=:0

#### Start Window manager
openbox &
sleep 0.5

#### Configure outputs & Rotation
read -r SCREEN_WIDTH SCREEN_HEIGHT < <(xrandr | grep "connected" | head -1 | grep -oE "[0-9]+x[0-9]+")
OUTPUT_NAME=$(xrandr | grep " connected" | awk '{print $1}')
xrandr --output "$OUTPUT_NAME" --auto --rotate "$ROTATE_DISPLAY"

#### Matchbox Virtual Keyboard
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Starting Matchbox Keyboard..."
    matchbox-keyboard &
fi

#### Start REST server
python3 /rest_server.py &

################################################################################
#### CHROMIUM CONFIGURATION & LAUNCH
################################################################################

ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
mkdir -p /tmp/chromium-profile

# --- CORRECTIF 2 : Utilisation du mode --kiosk pour un affichage plein écran total ---
CHROME_FLAGS="\
    --no-sandbox \
    --test-type \
    --kiosk \
    --window-position=0,0 \
    --window-size=$SCREEN_WIDTH,$SCREEN_HEIGHT \
    --enable-features=WebUIDisableNewBadgeStyle \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-infobars \
    --force-device-scale-factor=$ZOOM_DPI \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile"

[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

# --- CORRECTIF 3 : Nettoyage physique de l'écran juste avant Chromium ---
if [ -e /dev/tty0 ]; then
    clear > /dev/tty0 2>/dev/null || true
fi
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid black || true

# On cache ces logs de l'écran console mais on les garde dans HA
bashio::log.info "Launching Chromium to: $FULL_URL" > /dev/null

# Lancer Chromium
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!

################################################################################
#### AUTO-LOGIN LOGIC (Xdotool)
################################################################################
if [ "$AUTO_LOGIN" = true ]; then
    (
        LOGIN_DELAY_INT=${LOGIN_DELAY%.*}
        sleep $((LOGIN_DELAY_INT + 4))
        
        WINDOW_ID=$(xdotool search --class chromium | head -1)
        if [ -n "$WINDOW_ID" ]; then
            xdotool windowactivate --sync "$WINDOW_ID"
            sleep 2
            # Séquence de frappe
            xdotool mousemove --window "$WINDOW_ID" 960 400 click 1 sleep 1
            xdotool type --clearmodifiers --delay 100 "$HA_USERNAME"
            xdotool key Tab sleep 1
            xdotool type --clearmodifiers --delay 100 "$HA_PASSWORD"
            xdotool key Return
        fi
    ) &
fi

if [ "$DEBUG_MODE" = true ]; then
    tail -f /tmp/chromium.log &
fi

# Empêche le conteneur de se fermer
wait "$CHROME_PID"
sleep 5
tail -f /dev/null
