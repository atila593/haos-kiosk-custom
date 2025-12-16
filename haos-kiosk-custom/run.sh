#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

bashio::log.info "######## MODE RECONSTRUCTION ########"

# 1. LE HACK TTY0 (OBLIGATOIRE)
# Sans ça, Xorg n'a pas les droits et le tactile/souris meurent
TTY0_DELETED=""
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Application du hack TTY0..."
    mount -o remount,rw /dev || true
    rm -f /dev/tty0 && TTY0_DELETED=1
fi

# 2. DEMARRAGE XORG
# On lance le serveur de base
Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

# 3. GESTIONNAIRE DE FENETRES (OPENBOX)
# On le lance en premier pour qu'il accueille les autres fenêtres
openbox &
sleep 2

# 4. CLAVIER (PLACEMENT MANUEL)
# On le lance avant Chromium pour qu'il soit "dessous" au pire, mais présent
bashio::log.info "Lancement du clavier..."
matchbox-keyboard &
sleep 3
# On le déplace au milieu de l'écran pour être sûr de le voir
xdotool search --class "matchbox-keyboard" windowmove 100 400 2>/dev/null || true

# 5. CHROMIUM (MODE STABILITÉ MAXIMALE)
bashio::log.info "Lancement de Chromium en mode Software Rendering..."

# Ces drapeaux forcent Chromium à ne PAS toucher au GPU (évite les freeze)
CHROME_STABILITY_FLAGS="--no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --ignore-gpu-blocklist \
  --disable-accelerated-2d-canvas \
  --disable-gpu-rasterization"

chromium $CHROME_STABILITY_FLAGS \
  --start-fullscreen \
  --no-first-run \
  --user-data-dir=/tmp/chromium-profile \
  "http://192.168.1.142:8123" &
