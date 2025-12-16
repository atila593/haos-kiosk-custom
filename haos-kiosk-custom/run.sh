#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.7-touch-emergency-fix"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"

#### Clean up
TTY0_DELETED=""
cleanup() {
    local exit_code=$?
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Config
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
load_config_var ALLOW_USER_COMMANDS true

#### TTY Hack pour Xorg
if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0 && TTY0_DELETED=1
fi

#### Démarrage Xorg
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
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

#### 3. TACTILE (MODE BRUT)
if [ "$MAP_TOUCH_INPUTS" = true ]; then
    bashio::log.info "Mapping touch inputs (BRUTE FORCE)..."
    sleep 2
    # On mappe absolument TOUT ce qui ressemble à un pointeur vers l'écran HDMI
    # Si ça ne marche pas comme ça, c'est que le driver Xorg n'aime pas le mapping
    for id in $(xinput list --id-only); do
        xinput map-to-output "$id" "$OUTPUT_NAME" 2>/dev/null || true
    done
fi

#### 4. CLAVIER (TEST DE VISIBILITÉ MILIEU D'ÉCRAN)
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.info "Lancement du clavier..."
    matchbox-keyboard &
    sleep 5
    # On le place au milieu pour être SÛR de le voir
    xdotool search --class "matchbox-keyboard" windowmove 100 300 2>/dev/null || true
fi

#### 5. CHROMIUM (MODE FENÊTRE SIMPLE)
# On répare le bug du serveur REST
export ALLOW_USER_COMMANDS="${ALLOW_USER_COMMANDS:-true}"
python3 /rest_server.py &

ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Lancement de Chromium..."
# Utilisation de --window-size pour ne pas cacher le reste
chromium --no-sandbox --window-size=1920,1080 --window-position=0,0 --user-data-dir=/tmp/chromium-profile --force-device-scale-factor=$ZOOM_DPI --app="$FULL_URL" &
CHROME_PID=$!

wait "$CHROME_PID"
