#!/usr/bin/with-contenv bashio

# 1. Configuration
HA_URL=$(bashio::config 'ha_url' 'http://192.168.1.142:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')
USE_KEYBOARD=$(bashio::config 'onscreen_keyboard' 'true')
FINAL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Démarrage HAOSKiosk (Mode Privilégié Requis)..."

# 2. Montage du système de fichiers en lecture/écriture (pour le tactile)
mount -o remount,rw /sys 2>/dev/null || true
mount -o remount,rw /dev 2>/dev/null || true

# 3. Réveil forcé de l'USB et du Tactile
udevd --daemon || true
udevadm trigger || true
udevadm settle --timeout=5

# 4. Lancement de Xorg
rm -f /tmp/.X0-lock || true
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0

# Attente du serveur X
while ! xset -q > /dev/null 2>&1; do sleep 1; done

# 5. Mapping du Tactile (avec recherche large)
# On attend que xinput se réveille
sleep 3
bashio::log.info "Périphériques détectés : $(xinput list --name-only | tr '\n' ', ')"

TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)

if xinput list --name-only | grep -iq "Weida"; then
    # On utilise grep -i pour ignorer la casse
    ACTUAL_NAME=$(xinput list --name-only | grep -i "Weida" | head -n 1)
    xinput map-to-output "$ACTUAL_NAME" "$MAIN_SCREEN" || true
    bashio::log.info "SUCCÈS : Tactile [$ACTUAL_NAME] mappé sur $MAIN_SCREEN"
else
    bashio::log.warning "ÉCHEC : Tactile Weida toujours introuvable. Vérifiez le Mode Protégé."
fi

# 6. Window Manager et Clavier
openbox --config-file /etc/openbox/rc.xml &
if [ "$USE_KEYBOARD" = "true" ]; then
    matchbox-keyboard --daemon &
    python3 /rest_server.py &
fi

# 7. Lancement Chromium
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")
# Nettoyage console (pour tes logs à gauche)
dmesg -D 2>/dev/null || true
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
  "$FINAL_URL"
