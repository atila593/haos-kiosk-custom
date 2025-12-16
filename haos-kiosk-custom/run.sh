#!/usr/bin/with-contenv bashio

# Récupération des options utilisateur (avec valeurs par défaut)
HA_URL=$(bashio::config 'ha_url' 'http://homeassistant.local:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')
USE_KEYBOARD=$(bashio::config 'onscreen_keyboard' 'true')

# Construction propre de l'URL
FINAL_URL="${HA_URL}/${HA_DASHBOARD}"
FINAL_URL=$(echo "$FINAL_URL" | sed 's|//*|/|g' | sed 's|http:/|http://|g')

bashio::log.info "Démarrage de l'addon universel..."

# Nettoyage
rm -f /tmp/.X0-lock || true

# 1. Lancer Xorg
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0

# Attendre X11
while ! xset -q > /dev/null 2>&1; do sleep 1; done

# 2. Configurer le tactile Weida s'il est présent (automatique)
TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
if xinput list --name-only | grep -q "$TOUCH_NAME"; then
    MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_NAME" "$MAIN_SCREEN" || true
fi

# 3. Lancer Openbox avec une config qui force le clavier au-dessus
openbox --config-file /etc/openbox/rc.xml &

# 4. Lancer le clavier en mode "DOCK" (si activé)
if [ "$USE_KEYBOARD" = "true" ]; then
    bashio::log.info "Initialisation du clavier visuel (Matchbox)..."
    # Le mode "daemon" permet au clavier de rester en attente
    matchbox-keyboard --daemon & 
fi

# 5. Lancer Chromium
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")
bashio::log.info "Lancement de Chromium sur $FINAL_URL"

chromium \
  --no-sandbox \
  --kiosk \
  --no-first-run \
  --start-fullscreen \
  --disable-gpu \
  --disable-dev-shm-usage \
  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  --noerrdialogs \
  "$FINAL_URL"
