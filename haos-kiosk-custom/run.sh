#!/usr/bin/with-contenv bashio

# 1. Récupération des configurations
HA_URL=$(bashio::config 'ha_url')
HA_DASHBOARD=$(bashio::config 'ha_dashboard')
ZOOM_LEVEL=$(bashio::config 'zoom_level')
CURSOR_TIMEOUT=$(bashio::config 'cursor_timeout')

# Construction de l'URL
if [ -z "$HA_DASHBOARD" ]; then
    FINAL_URL="$HA_URL"
else
    # Nettoyage pour éviter les doubles slashes
    HA_URL_STRIPPED=$(echo "$HA_URL" | sed 's:/*$::')
    DASHBOARD_STRIPPED=$(echo "$HA_DASHBOARD" | sed 's:^/*::')
    FINAL_URL="${HA_URL_STRIPPED}/${DASHBOARD_STRIPPED}"
fi

# 2. Préparation du matériel (Mode Privilégié requis)
bashio::log.info "Initialisation du système graphique et tactile..."

# Hack TTY pour éviter les conflits d'affichage
if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0
fi



# On s'assure que les entrées sont accessibles
chmod -R 777 /dev/input || true










# 3. Lancement du serveur X
# On lance Xorg en arrière-plan
Xorg -nocursor </dev/null &
sleep 4
export DISPLAY=:0

# 4. Configuration de l'affichage
# On désactive la mise en veille et l'économiseur d'écran
xset s off
xset -dpms
xset s noblank

# On récupère l'ID du tactile dynamiquement (ton fameux Weida id=9)
TOUCH_ID=$(xinput list --id-only "Weida Hi-Tech CoolTouchR System" 2>/dev/null)
if [ ! -z "$TOUCH_ID" ]; then
    bashio::log.info "Tactile Weida détecté (ID: $TOUCH_ID). Mappage sur l'écran..."
    # On mappe le tactile sur la première sortie écran trouvée
    SCREEN_NAME=$(xrandr | grep " connected" | awk '{print $1}' | head -n 1)
    xinput map-to-output "$TOUCH_ID" "$SCREEN_NAME" || true
fi

# 5. Lancement des services UI
openbox &
if bashio::config.true 'onscreen_keyboard'; then
    matchbox-keyboard &
fi

# 6. Lancement de Chromium
bashio::log.info "Lancement du Kiosk à l'adresse : $FINAL_URL"

# Calcul du facteur de zoom pour Chromium
# Chromium utilise un facteur où 100% = 1.0

CHROME_ZOOM=$(awk "BEGIN {print $ZOOM_LEVEL/100}")



chromium \
  --no-sandbox \
  --kiosk \
  --start-fullscreen \
  --no-first-run \

  --disable-gpu \

  --disable-dev-shm-usage \
  --disable-session-crashed-bubble \
  --disable-infobars \

  --force-device-scale-factor="$CHROME_ZOOM" \
  --touch-events=enabled \
  --autoplay-policy=no-user-gesture-required \
  "$FINAL_URL"
