#!/usr/bin/with-contenv bashio

# 1. Nettoyage des logs à gauche (Nécessite Mode Protégé OFF)
dmesg -D 2>/dev/null || true

# 2. Variables de configuration
HA_URL=$(bashio::config 'ha_url' 'http://192.168.1.142:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')
USE_KEYBOARD=$(bashio::config 'onscreen_keyboard' 'true')

FINAL_URL="${HA_URL}/${HA_DASHBOARD}"
FINAL_URL=$(echo "$FINAL_URL" | sed 's|//*|/|g' | sed 's|http:/|http://|g')

bashio::log.info "Démarrage HAOSKiosk (Fix Tactile Weida)..."

# 3. Préparation Système (Indispensable pour le tactile)
mkdir -p /run/dbus || true
dbus-daemon --system --fork || true
# --- LIGNE CRUCIALE : Réveille les pilotes USB/Tactile ---
udevd --daemon || true
udevadm trigger || true
udevadm settle --timeout=5

# 4. Lancement de Xorg
rm -f /tmp/.X0-lock || true
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0

# Attente du serveur X
while ! xset -q > /dev/null 2>&1; do sleep 1; done

# 5. Gestion du Tactile Weida
TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
# On donne un petit délai pour que Xinput détecte le matériel
sleep 2 
if xinput list --name-only | grep -q "$TOUCH_NAME"; then
    MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_NAME" "$MAIN_SCREEN" || true
    bashio::log.info "Tactile Weida détecté et mappé sur $MAIN_SCREEN"
else
    bashio::log.warning "Tactile Weida non trouvé par xinput !"
fi

# 6. Gestionnaire de fenêtres
openbox --config-file /etc/openbox/rc.xml &
sleep 1

# 7. Clavier et Serveur de contrôle
if [ "$USE_KEYBOARD" = "true" ]; then
    matchbox-keyboard --daemon &
    python3 /rest_server.py &
fi

# 8. Lancement de Chromium (Optimisé Tactile)
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")
clear > /dev/tty0 2>/dev/null || true

chromium \
  --no-sandbox \
  --kiosk \
  --user-data-dir=/tmp/chromium-profile \
  --disable-gpu \
  --disable-software-rasterizer \
  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  --enable-viewport \
  --autoplay-policy=no-user-gesture-required \
  "$FINAL_URL"
