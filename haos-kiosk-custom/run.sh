#!/usr/bin/with-contenv bashio

# 1. Chargement des options (config.json)
HA_URL=$(bashio::config 'ha_url' 'http://homeassistant.local:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')

# Construction de l'URL finale
FINAL_URL="${HA_URL}/${HA_DASHBOARD}"
FINAL_URL=$(echo "$FINAL_URL" | sed 's|//*|/|g' | sed 's|http:/|http://|g')

bashio::log.info "Démarrage du Kiosk..."
bashio::log.info "URL cible : $FINAL_URL"

# 2. Nettoyage des fichiers temporaires
rm -f /tmp/.X0-lock || true

# 3. Lancement de Xorg en arrière-plan
# On redirige les erreurs xkbcomp vers /dev/null pour nettoyer tes logs
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
X_PID=$!

# Attendre que X11 soit prêt
MAX_RETRIES=10
COUNT=0
while ! xset -q > /dev/null 2>&1; do
    sleep 1
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        bashio::log.error "Xorg n'a pas démarré à temps."
        exit 1
    fi
done

export DISPLAY=:0

# 4. Configuration de l'écran (Désactive la veille)
xset s off
xset -dpms
xset s noblank

# 5. Gestion du Tactile (Auto-détection du Weida)
TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
if xinput list --name-only | grep -q "$TOUCH_NAME"; then
    bashio::log.info "Tactile détecté et configuré."
    # On mappe le tactile à l'écran principal
    MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_NAME" "$MAIN_SCREEN" || true
fi

# 6. Gestionnaire de fenêtres (Openbox)
openbox &

# 7. Lancement de Chromium
# --no-first-run : évite les popups de bienvenue
# --force-device-scale-factor : gère le zoom
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")

bashio::log.info "Lancement de Chromium (Zoom: $CHROME_ZOOM)..."

chromium \
  --no-sandbox \
  --kiosk \
  --no-first-run \
  --start-fullscreen \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  "$FINAL_URL"
