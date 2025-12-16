#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.3-fix-bootloop"

# On essaie dmesg, mais on ne crash pas si ça échoue (cas du mode protégé activé)
dmesg -D 2>/dev/null || bashio::log.warning "Impossible de couper dmesg (Désactivez le 'Mode Protégé' de l'addon)"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'\nbashio::log.info "######## Starting HAOSKiosk (Fix Edition) ########"

# ... [Garder tes fonctions load_config_var ici] ...

#### CRITICAL HACK: Delete /dev/tty0 avec sécurité
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Nettoyage de tty0..."
    mount -o remount,rw /dev 2>/dev/null || true
    rm -f /dev/tty0 || true
    TTY0_DELETED=1
fi

# [On saute la détection DRM pour aller plus vite]
selected_card="card0"

#### Start Xorg
rm -rf /tmp/.X*-lock
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "fbdev"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Card0"
EndSection
EOF

bashio::log.info "Starting X..."
Xorg -nocursor </dev/null >/dev/null 2>&1 &
sleep 4
export DISPLAY=:0

# Window Manager
openbox &
sleep 1

# Dimensions (On force si xrandr échoue)
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080

#### REST SERVER & KEYBOARD
python3 /rest_server.py &
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    matchbox-keyboard &
fi

################################################################################
#### CHROMIUM LAUNCH (PROPRE)
################################################################################

ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
mkdir -p /tmp/chromium-profile

CHROME_FLAGS="\
    --no-sandbox \
    --test-type \
    --kiosk \
    --window-position=0,0 \
    --window-size=$SCREEN_WIDTH,$SCREEN_HEIGHT \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-infobars \
    --force-device-scale-factor=$ZOOM_DPI \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile"

[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

FULL_URL="${HA_URL}"
[ -n "$HA_DASHBOARD" ] && FULL_URL="${HA_URL}/${HA_DASHBOARD}"

# Nettoyage final invisible sur l'écran
clear > /dev/tty0 2>/dev/null || true
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid black || true

bashio::log.info "Lancement de Chromium..."
# On lance Chromium SANS redirection tail pour éviter de polluer l'écran
chromium $CHROME_FLAGS "$FULL_URL" > /dev/null 2>&1 &
CHROME_PID=$!

# Bloquer le script ici pour éviter le redémarrage s6-rc
wait "$CHROME_PID"
sleep 5
tail -f /dev/null
