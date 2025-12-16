#!/usr/bin/with-contenv bashio

# Variables
HA_URL=$(bashio::config 'ha_url' 'http://homeassistant.local:8123')
HA_DASHBOARD=$(bashio::config 'ha_dashboard' '')
FINAL_URL="${HA_URL}/${HA_DASHBOARD}"

bashio::log.info "Démarrage du Kiosk..."

# Préparation X11
rm -f /tmp/.X0-lock || true
Xorg -nocursor :0 vt1 &
export DISPLAY=:0
sleep 2

# Lancement des composants en arrière-plan
matchbox-keyboard --daemon &
# ON UTILISE /app/ car c'est là que Docker copie le fichier
export REST_PORT=$(bashio::config 'rest_port' '8080')
python3 /app/rest_server.py & 

# Chromium (Processus principal qui garde l'addon ouvert)
chromium \
  --no-sandbox \
  --kiosk \
  --start-fullscreen \
  --disable-gpu \
  "$FINAL_URL"
