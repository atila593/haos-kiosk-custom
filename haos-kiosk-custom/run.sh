#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.3-touch-fixed"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"

#### Clean up on exit
cleanup() {
    local exit_code=$?
    jobs -p | xargs -r kill 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Chargement Configuration
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
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT fr
load_config_var ONSCREEN_KEYBOARD false
load_config_var REST_PORT 8080
load_config_var ALLOW_USER_COMMANDS false

#### Démarrage Services de base (Xorg)
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "modesetting"
EndSection
EOF

# Lancement Xorg
Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

#### 1. LANCER LE GESTIONNAIRE DE FENÊTRES (OPENBOX)
bashio::log.info "Starting Openbox Window Manager..."
openbox &
sleep 2

#### 2. CONFIGURATION ÉCRAN ET ROTATION
OUTPUT_NAME=$(xrandr --query | grep " connected" | head -n "$OUTPUT_NUMBER" | tail -n 1 | cut -d' ' -f1)
xrandr --output "$OUTPUT_NAME" --primary --auto --rotate "${ROTATE_DISPLAY}"
setxkbmap "$KEYBOARD_LAYOUT"

#### 3. FIX TACTILE (CRITIQUE : Après Openbox et Rotation)
if [ "$MAP_TOUCH_INPUTS" = true ]; then
    bashio::log.info "Mapping touch inputs to $OUTPUT_NAME..."
    # On attend que les périphériques soient bien enregistrés par X11
    sleep 2
    xinput list --id-only | while read -r id; do
        if xinput list-props "$id" 2>/dev/null | grep -q "Coordinate Transformation Matrix"; then
            bashio::log.info "Found touch device ID $id, mapping to $OUTPUT_NAME"
            xinput map-to-output "$id" "$OUTPUT_NAME" || true
        fi
    done
fi

#### 4. LANCER LE CLAVIER (MATCHBOX)
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Starting Matchbox Virtual Keyboard..."
    # On lance matchbox en mode "sticky" (toujours visible)
    matchbox-keyboard &
    sleep 2
    # On utilise xdotool pour s'assurer qu'il est en bas et n'empêche pas le tactile
    xdotool search --class "matchbox-keyboard" windowmove 0 700 2>/dev/null || true
fi

#### 5. REST SERVER
python3 /rest_server.py &

#### 6. CHROMIUM
ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
mkdir -p /tmp/chromium-profile
CHROME_FLAGS="--no-sandbox --start-fullscreen --disable-infobars --force-device-scale-factor=$ZOOM_DPI --no-first-run --user-data-dir=/tmp/chromium-profile"

FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Launching Chromium..."
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!

wait "$CHROME_PID"
