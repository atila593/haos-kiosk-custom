#!/usr/bin/with-contenv bashio

# 1. Variables de configuration
HA_URL=$(bashio::config 'ha_url' 'http://homeassistant.local:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
ZOOM_LEVEL=$(bashio::config 'zoom_level' '100')
USE_KEYBOARD=$(bashio::config 'onscreen_keyboard' 'true')

FINAL_URL="${HA_URL}/${HA_DASHBOARD}"
FINAL_URL=$(echo "$FINAL_URL" | sed 's|//*|/|g' | sed 's|http:/|http://|g')

bashio::log.info "Démarrage du Kiosk Universel..."

# 2. Nettoyage et préparation
rm -f /tmp/.X0-lock || true
mkdir -p /run/dbus || true
dbus-daemon --system --fork || true

# 3. Lancement de Xorg (Redirection des erreurs pour des logs propres)
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0

# Attente active du serveur X
while ! xset -q > /dev/null 2>&1; do sleep 1; done

# 4. Gestion du Tactile (Automatique pour tout le monde)
TOUCH_NAME="Weida Hi-Tech CoolTouchR System"
if xinput list --name-only | grep -q "$TOUCH_NAME"; then
    MAIN_SCREEN=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_NAME" "$MAIN_SCREEN" || true
    bashio::log.info "Tactile Weida mappé sur $MAIN_SCREEN"
fi

# 5. Gestionnaire de fenêtres (Indispensable pour le clavier)
openbox --config-file /etc/openbox/rc.xml &

# 6. Clavier et Serveur de contrôle
if [ "$USE_KEYBOARD" = "true" ]; then
    bashio::log.info "Démarrage du clavier et du serveur de contrôle..."
    
    # Exporter les variables pour Python
    export ALLOW_USER_COMMANDS=$(bashio::config 'allow_user_commands' 'false')
    export REST_PORT=$(bashio::config 'rest_port' '8080')
    export DISPLAY=:0  # On s'assure qu'il est bien exporté pour ce sous-processus
    
    # Lancement du clavier Matchbox en mode daemon
    matchbox-keyboard --daemon &
    
    # Lancement du serveur (Note le chemin /app/)
    python3 /app/rest_server.py &
    
    bashio::log.info "Serveur REST lancé sur le port $REST_PORT"
fi

# 7. Lancement de Chromium (Optimisé pour éviter les erreurs GPU/Vulkan)
CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")

chromium \
  --no-sandbox \
  --kiosk \
  --start-fullscreen \
  --no-first-run \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --disable-session-crashed-bubble \
  --noerrdialogs \
  --disable-infobars \
  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  --autoplay-policy=no-user-gesture-required \
  "$FINAL_URL" &

# 8. BOUCLE DE MAINTIEN (ESSENTIEL)
# Cela empêche l'addon de s'arrêter si Chromium crash
bashio::log.info "Kiosk prêt et stable. En attente de commandes REST..."

while true; do
    sleep 60
done
