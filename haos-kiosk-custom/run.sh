#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.5-touch-auto-detect"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"

#### Nettoyage à la sortie
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
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT fr
load_config_var ONSCREEN_KEYBOARD true
load_config_var REST_PORT 8080
load_config_var ALLOW_USER_COMMANDS true

#### Hack TTY pour HAOS
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
bashio::log.info "Démarrage Openbox..."
openbox &
sleep 2

#### 2. CONFIGURATION ÉCRAN
OUTPUT_NAME=$(xrandr --query | grep " connected" | head -n "$OUTPUT_NUMBER" | tail -n 1 | cut -d' ' -f1)
xrandr --output "$OUTPUT_NAME" --primary --auto --rotate "${ROTATE_DISPLAY}"
setxkbmap "$KEYBOARD_LAYOUT"

#### 3. TACTILE (DÉTECTION AUTOMATIQUE AMÉLIORÉE)
if [ "$MAP_TOUCH_INPUTS" = true ]; then
    bashio::log.info "Recherche du périphérique tactile..."
    sleep 2
    # On cherche les IDs des périphériques qui sont des esclaves pointeurs (Floating/Master pointer)
    # et on filtre pour exclure les claviers/boutons
    xinput list --id-only | while read -r id; do
        props=$(xinput list-props "$id" 2>/dev/null)
        # Un écran tactile a presque toujours une matrice de transformation et n'est pas un clavier
        if echo "$props" | grep -q "Coordinate Transformation Matrix" && ! echo "$props" | grep -q "Keyboard"; then
            bashio::log.info "Périphérique tactile détecté (ID: $id). Mapping vers $OUTPUT_NAME..."
            xinput map-to-output "$id" "$OUTPUT_NAME" || true
        fi
    done
fi

#### 4. CLAVIER TACTILE (SANS OPTIONS QUI PLANTENT)
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Démarrage du clavier Matchbox..."
    matchbox-keyboard & 
    sleep 3
    # On place le clavier en bas (30% de l'écran)
    xdotool search --class "matchbox-keyboard" windowmove 0 750 2>/dev/null || true
    xdotool search --class "matchbox-keyboard" windowsize 100% 25% 2>/dev/null || true
fi

#### 5. SERVICES ET CHROMIUM
python3 /rest_server.py &

ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
mkdir -p /tmp/chromium-profile
CHROME_FLAGS="--no-sandbox --start-fullscreen --disable-infobars --force-device-scale-factor=$ZOOM_DPI --no-first-run --user-data-dir=/tmp/chromium-profile"

FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Lancement de Chromium..."
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!

wait "$CHROME_PID"
