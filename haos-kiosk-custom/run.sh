#!/usr/bin/with-contenv bashio

# --- HACK PERMISSIONS ---
if [ -e "/dev/tty0" ]; then
    mount -o remount,rw /dev || true
    rm -f /dev/tty0
fi

# Démarrage de UDEV (crucial pour peupler /dev/input)
/sbin/udevd --daemon || true
udevadm trigger || true

# Forcer les droits sur les ports USB/Entrées
chmod -R 777 /dev/input || true

# --- CONFIG XORG TACTILE ---
mkdir -p /usr/share/X11/xorg.conf.d/
cat > /usr/share/X11/xorg.conf.d/99-touchscreen.conf << 'EOF'
Section "InputClass"
    Identifier "touchscreen catchall"
    MatchIsTouchscreen "on"
    MatchDevicePath "/dev/input/event*"
    Driver "evdev"
EndSection
EOF

# --- DEMARRAGE ---
Xorg -nocursor </dev/null &
sleep 5
export DISPLAY=:0

# Diagnostic : On vérifie si udev a fait son travail
bashio::log.info "Vérification des périphériques d'entrée :"
xinput list

openbox &
matchbox-keyboard &
sleep 3

# Chromium avec les drapeaux de stabilité
chromium \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --start-fullscreen \
  --no-first-run \
  "http://192.168.1.142:8123"
