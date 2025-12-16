#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.6-dock-mode"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"

#### Clean up on exit
TTY0_DELETED=""
cleanup() {
    local exit_code=$?
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Configuration
load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local VALUE
    if bashio::config.exists "${VAR_NAME,,}"; then VALUE="$(bashio::config "${VAR_NAME,,}")"; else VALUE="$DEFAULT"; fi
    [ "$VALUE" = "null" ] || [ -z "$VALUE" ] && VALUE="$DEFAULT"
    export "$VAR_NAME"="$VALUE"
    bashio::log.info "$VAR_NAME=$VALUE"
}

load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var ZOOM_LEVEL 100
load_config_var OUTPUT_NUMBER 1
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var KEYBOARD_LAYOUT fr
load_config_var ONSCREEN_KEYBOARD true

#### Hack TTY
if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0 && TTY0_DELETED=1
fi

#### Démarrage Xorg
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "modesetting"
EndSection
EOF

Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

#### 1. GESTIONNAIRE DE FENÊTRES
openbox &
sleep 2

#### 2. CONFIGURATION ÉCRAN
OUTPUT_NAME=$(xrandr --query | grep " connected" | head -n "$OUTPUT_NUMBER" | tail -n 1 | cut -d' ' -f1)
xrandr --output "$OUTPUT_NAME" --primary --auto --rotate "${ROTATE_DISPLAY}"
setxkbmap "$KEYBOARD_LAYOUT"

#### 3. TACTILE (SANS ERREUR)
if [ "$MAP_TOUCH_INPUTS" = true ]; then
    bashio::log.info "Mapping touch inputs..."
    sleep 2
    xinput list --id-only | while read -r id; do
        xinput map-to-output "$id" "$OUTPUT_NAME" 2>/dev/null || true
    done
fi

#### 4. CLAVIER (MODE DOCK)
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Lancement du clavier en mode Dock..."
    # On lance matchbox
    matchbox-keyboard &
    sleep 4
    
    # On force le type de fenêtre à "DOCK" pour qu'il soit protégé
    # Et on le place en bas de l'écran (y=780 pour un écran 1080p)
    xprop -name "matchbox-keyboard" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DOCK 2>/dev/null || true
    xdotool search --class "matchbox-keyboard" windowmove 0 780 2>/dev/null || true
    xdotool search --class "matchbox-keyboard" windowsize 100% 300 2>/dev/null || true
fi

#### 5. CHROMIUM (MODE APP POUR ÉVITER LE PLEIN ÉCRAN TOTAL)
python3 /rest_server.py &

ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Lancement de Chromium..."
# --app permet d'avoir le dashboard sans barres d'outils mais laisse le dock visible
chromium --no-sandbox --start-maximized --user-data-dir=/tmp/chromium-profile --force-device-scale-factor=$ZOOM_DPI --app="$FULL_URL" &
CHROME_PID=$!

wait "$CHROME_PID"
