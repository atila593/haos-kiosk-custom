#!/usr/bin/with-contenv bashio

# 1. Silence total du noyau (Nettoyage logs à gauche)
dmesg -D 2>/dev/null || true

# 2. Variables de configuration
HA_URL=$(bashio::config 'ha_url' 'http://homeassistant.local:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')
USE_KEYBOARD=$(bashio::config 'onscreen_keyboard' 'true')

FINAL_URL="${HA_URL}/${HA_DASHBOARD}"
FINAL_URL=$(echo "$FINAL_URL" | sed 's|//*|/|g' | sed 's|http:/|http://|g')

bashio::log.info "Démarrage du Kiosk Universel (Fix Tactile)..."

# 3. Nettoyage et préparation (IMPORTANT pour le tactile)
rm -rf /tmp/.X*-lock || true
mkdir -p /run/dbus || true
dbus-daemon --system --fork || true
# On ajoute le bus session, souvent nécessaire pour les pilotes tactiles récents
export DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)

# 4. Lancement de Xorg
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0

# Attente active du serveur X
while ! xset -q > /dev/null 2>&1; do sleep 1; done

# 5. Gestion du Tactile Weida
TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
# On force un rafraîchissement des périphériques
udevadm trigger 2>/dev/null || true
if xinput list --name-only | grep -q "$TOUCH_NAME"; then
    MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_NAME" "$MAIN_SCREEN" || true
    bashio::log.info "Tactile Weida mappé sur $MAIN_SCREEN"
fi

# 6. Gestionnaire de fenêtres (Indispensable pour le clavier)
openbox --config-file /etc/openbox/rc.xml &
sleep 1

# 7. Clavier et Serveur de contrôle
if [ "$USE_KEYBOARD" = "true" ]; then
    bashio::log.info "Démarrage du clavier et du serveur de contrôle..."
    matchbox-keyboard &
    python3 /rest_server.py &
fi

# 8. Lancement de Chromium (AVEC LES FIX TACTILES)
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")

# Nettoyage console final avant l'affichage
clear > /dev/tty0 2>/dev/null || true

chromium \
  --no-sandbox \
  --kiosk \
  --no-first-run \
  --user-data-dir=/tmp/chromium-profile \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --disable-session-crashed-bubble \
  --noerrdialogs \
  --disable-infobars \
  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  --enable-viewport \
  --autoplay-policy=no-user-gesture-required \
  "$FINAL_URL"
