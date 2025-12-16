#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

bashio::log.info "######## MODE STABILITÉ FINALE ########"

# 1. HACK TTY0 (Permissions)
TTY0_DELETED=""
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Application du hack TTY0..."
    mount -o remount,rw /dev || true
    rm -f /dev/tty0 && TTY0_DELETED=1
fi

# Force la détection du tactile par le pilote evdev
mkdir -p /usr/share/X11/xorg.conf.d/
cat > /usr/share/X11/xorg.conf.d/99-touchscreen.conf << 'EOF'
Section "InputClass"
    Identifier "touchscreen catchall"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "evdev"
EndSection
EOF

# 2. XORG
Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

# 3. OPENBOX
openbox &
sleep 2

# 4. CLAVIER
bashio::log.info "Lancement du clavier..."
matchbox-keyboard &
sleep 3
xdotool search --class "matchbox-keyboard" windowmove 100 400 2>/dev/null || true

# 5. CHROMIUM (SANS GPU + ATTENTE)
bashio::log.info "Lancement de Chromium..."
# Note : on retire le '&' à la fin de la commande chromium pour que le script "attende" ici
chromium \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --start-fullscreen \
  --no-first-run \
  --user-data-dir=/tmp/chromium-profile \
  "http://192.168.1.142:8123"

# Si chromium s'arrête, on recrée le TTY avant de sortir
[ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
bashio::log.info "Chromium s'est arrêté."
