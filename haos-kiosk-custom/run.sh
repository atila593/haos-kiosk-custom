#!/usr/bin/with-contenv bashio

bashio::log.info "Démarrage en mode ultra-stable..."

# Nettoyage forcé des verrous X11 et D-Bus
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 || true
mkdir -p /run/dbus || true

# Lancement D-Bus en mode safe
dbus-daemon --system --fork || true

# Lancement Xorg
Xorg -nocursor :0 vt1 > /dev/null 2>&1 &
export DISPLAY=:0
sleep 3

# Lancement Openbox (Gestionnaire de fenêtres)
openbox --config-file /etc/openbox/rc.xml &
sleep 1

# Lancement de ton serveur REST Python (Important : en arrière-plan avec &)
export REST_PORT=$(bashio::config 'rest_port' '8080')
python3 /app/rest_server.py &
bashio::log.info "Serveur REST démarré sur le port $REST_PORT"

# Lancement de Chromium en mode "Don't Die"
# On le met dans une boucle : s'il crash, il se relance tout seul
(
  while true; do
    bashio::log.info "Lancement de Chromium..."
    chromium \
      --no-sandbox \
      --kiosk \
      --disable-gpu \
      --disable-software-rasterizer \
      --noerrdialogs \
      --disable-infobars \
      "$(bashio::config 'ha_url' 'http://homeassistant.local:8123')"
    bashio::log.warn "Chromium s'est arrêté inopinément, relance dans 5 secondes..."
    sleep 5
  done
) &

# BOUCLE INFINIE FINALE : Empêche l'addon de mourir
bashio::log.info "Conteneur verrouillé pour rester allumé."
while true; do
    sleep 60
done
