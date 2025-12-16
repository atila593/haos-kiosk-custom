#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

bashio::log.info "######## PHASE DE DÉTECTION TACTILE ########"

# 1. HACK TTY0 (Indispensable)
if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0
fi

# 2. XORG
Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

# 3. DIAGNOSTIC MATÉRIEL (Regarde bien les logs après avoir mis ça)
bashio::log.info "Liste des périphériques détectés :"
xinput list || bashio::log.error "Impossible de lister les périphériques !"

# 4. OPENBOX & CLAVIER
openbox &
sleep 2
matchbox-keyboard &
sleep 3
# On place le clavier bien en évidence
xdotool search --class "matchbox-keyboard" windowmove 0 300 2>/dev/null || true

# 5. CHROMIUM (MODE STABLE)
bashio::log.info "Lancement de Chromium..."
chromium \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --start-fullscreen \
  --no-first-run \
  --user-data-dir=/tmp/chromium-profile \
  "http://192.168.1.142:8123"
