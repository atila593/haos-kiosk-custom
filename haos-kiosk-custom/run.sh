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

# 5. CHROMIUM (MODE SECURITE MAXIMALE)
# On désactive le GPU pour éviter les freeze du tactile
bashio::log.info "Lancement de Chromium..."
chromium \
  --no-sandbox \
  --disable-gpu \
  --start-fullscreen \
  --no-first-run \
  --user-data-dir=/tmp/chromium-profile \
  "http://192.168.1.142:8123" &

# On recrée le tty0 si on sort pour ne pas casser HAOS
cleanup() {
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit 0
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

wait
