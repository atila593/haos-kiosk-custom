#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.2-matchbox-fixed"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"
ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant') HAOS=$(echo "$ha_info" | jq -r '.hassos') MACHINE=$(echo "$ha_info" | jq -r '.machine') ARCH=$(echo "$ha_info" | jq -r '.arch')"

#### Clean up on exit:
TTY0_DELETED=""
cleanup() {
    local exit_code=$?
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Load Config
load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"
    local VALUE
    if declare -p "$VAR_NAME" >/dev/null 2>&1; then VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then VALUE="$(bashio::config "${VAR_NAME,,}")"
    else VALUE="$DEFAULT"; fi
    [ "$VALUE" = "null" ] || [ -z "$VALUE" ] && VALUE="$DEFAULT"
    printf -v "$VAR_NAME" '%s' "$VALUE"
    eval "export $VAR_NAME"
    [ -z "$MASK" ] && bashio::log.info "$VAR_NAME=$VALUE" || bashio::log.info "$VAR_NAME=XXXXXX"
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
load_config_var REST_PORT 8080
load_config_var ALLOW_USER_COMMANDS false
load_config_var DEBUG_MODE false

AUTO_LOGIN=$([[ -n "$HA_USERNAME" && -n "$HA_PASSWORD" ]] && echo true || echo false)

#### Start Services (Dbus, TTY Hack, Udev)
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
export DBUS_SESSION_BUS_ADDRESS

if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0 && TTY0_DELETED=1
fi

udevd --daemon && udevadm trigger && udevadm settle --timeout=10

#### Start Xorg
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "modesetting"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Card0"
EndSection
EOF

Xorg $([ "$CURSOR_TIMEOUT" -lt 0 ] && echo "-nocursor") </dev/null &
sleep 5
export DISPLAY=:0

if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || true
fi

#### Configure Display & Rotation
readarray -t OUTPUTS < <(xrandr --query | awk '/ connected/ {print $1}')
[ ${#OUTPUTS[@]} -eq 0 ] && bashio::log.error "No connected outputs" && exit 1
OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}"

for OUTPUT in "${OUTPUTS[@]}"; do
    if [ "$OUTPUT" = "$OUTPUT_NAME" ]; then
        xrandr --output "$OUTPUT_NAME" --primary --auto --rotate "${ROTATE_DISPLAY}"
    else
        xrandr --output "$OUTPUT" --off
    fi
done

# Map Touch
if [ "$MAP_TOUCH_INPUTS" = true ]; then
    xinput list --id-only | while read -r id; do
        xinput map-to-output "$id" "$OUTPUT_NAME" 2>/dev/null || true
    done
fi

setxkbmap "$KEYBOARD_LAYOUT"
read -r SCREEN_WIDTH SCREEN_HEIGHT < <(xrandr --query --current | grep "^$OUTPUT_NAME " | sed -n "s/^$OUTPUT_NAME connected.* \([0-9]\+\)x\([0-9]\+\)+.*$/\1 \2/p")

#### WINDOW MANAGER & KEYBOARD (Lancement critique)
bashio::log.info "Starting Window Manager (Openbox)..."
openbox &
sleep 1

if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Starting Matchbox Virtual Keyboard..."
    matchbox-keyboard &
    sleep 2
fi

#### Start REST server
python3 /rest_server.py &

#### Chromium Launch
ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
mkdir -p /tmp/chromium-profile

CHROME_FLAGS="\
    --no-sandbox \
    --start-fullscreen \
    --disable-infobars \
    --force-device-scale-factor=$ZOOM_DPI \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile"

[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Launching Chromium to: $FULL_URL"
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!

#### Auto-Login Sequence (xdotool)
if [ "$AUTO_LOGIN" = true ]; then
    (
        sleep $(( ${LOGIN_DELAY%.*} + 5 ))
        WINDOW_ID=$(xdotool search --class chromium | head -1)
        if [ -n "$WINDOW_ID" ]; then
            xdotool windowactivate --sync "$WINDOW_ID"
            xdotool mousemove --window "$WINDOW_ID" 960 420 click 1
            xdotool type --delay 120 "$HA_USERNAME"
            xdotool key Tab
            xdotool type --delay 120 "$HA_PASSWORD"
            xdotool key Return
        fi
    ) &
fi

wait "$CHROME_PID"
