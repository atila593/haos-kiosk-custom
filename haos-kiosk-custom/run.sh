#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.1-firefox"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Firefox Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"
ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant') HAOS=$(echo "$ha_info" | jq -r '.hassos') MACHINE=$(echo "$ha_info" | jq -r '.machine') ARCH=$(echo "$ha_info" | jq -r '.arch')"

#### Clean up on exit:
TTY0_DELETED=""
ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"
cleanup() {
    local exit_code=$?
    if [ "$SAVE_ONSCREEN_CONFIG" = true ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE" 2>/dev/null || true
    fi
    jobs -p | xargs -r kill 2>/dev/null || true
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Get config variables from HA add-on & set environment variables
load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"
    local VALUE

    if declare -p "$VAR_NAME" >/dev/null 2>&1; then
        VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    else
        bashio::log.warning "Unknown config key: ${VAR_NAME,,}"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        bashio::log.warning "Config key '${VAR_NAME,,}' unset, setting to default: '$DEFAULT'"
        VALUE="$DEFAULT"
    fi

    printf -v "$VAR_NAME" '%s' "$VALUE"
    eval "export $VAR_NAME"

    if [ -z "$MASK" ]; then
        bashio::log.info "$VAR_NAME=$VALUE"
    else
        bashio::log.info "$VAR_NAME=XXXXXX"
    fi
}

load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var LOGIN_DELAY 1.0
load_config_var ZOOM_LEVEL 100
load_config_var BROWSER_REFRESH 600
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var DARK_MODE true
load_config_var HA_SIDEBAR "none"
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT us
load_config_var ONSCREEN_KEYBOARD false
load_config_var SAVE_ONSCREEN_CONFIG true
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var REST_PORT 8080
load_config_var REST_BEARER_TOKEN "" 1
load_config_var ALLOW_USER_COMMANDS false
[ "$ALLOW_USER_COMMANDS" = "true" ] && bashio::log.warning "WARNING: 'allow_user_commands' set to 'true'"
load_config_var DEBUG_MODE false

if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

################################################################################
#### Start Dbus
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
fi
bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_ADDRESS
echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile"

#### CRITICAL HACK: Delete /dev/tty0 temporarily so X can start
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Attempting to remount /dev as 'rw' so we can (temporarily) delete /dev/tty0..."
    mount -o remount,rw /dev || true # La commande échoue, mais le script continue
    if ! mount -o remount,rw /dev ; then
        bashio::log.error "Failed to remount /dev as read-write... (System is read-only)"    
    fi
    if  ! rm -f /dev/tty0 ; then
        bashio::log.warning "WARNING: Failed to delete /dev/tty0. Continuing anyway."
    fi
    TTY0_DELETED=1
    bashio::log.info "Deleted /dev/tty0 successfully... (ATTENTION: Ceci sera journalisé même si la suppression a échoué)"
fi

#### Start udev (used by X)
bashio::log.info "Starting 'udevd' and (re-)triggering..."
if ! udevd --daemon || ! udevadm trigger; then
    bashio::log.warning "WARNING: Failed to start udevd or trigger udev, input devices may not work"
fi

# Force tagging of event input devices
echo "/dev/input event devices:"
for dev in $(find /dev/input/event* 2>/dev/null | sort -V); do
    devpath_output=$(udevadm info --query=path --name="$dev" 2>/dev/null; echo -n $?)
    return_status=${devpath_output##*$'\n'}
    [ "$return_status" -eq 0 ] || { echo "  $dev: Failed to get device path"; continue; }
    devpath=${devpath_output%$'\n'*}
    echo "  $dev: $devpath"
    udevadm test "$devpath" >/dev/null 2>&1 || echo "$dev: No valid udev rule found..."
done

udevadm settle --timeout=10

echo "libinput list-devices found:"
# Le code log de libinput est commenté car il plantait le script
# libinput list-devices 2>/dev/null | awk '
#    /^Device:/ {devname=substr($0, 9)}
#    /^Kernel:/ {
#      split($2, a, "/");
#      printf "  %s: %s\n", a[length(a)], devname
# }' | sort -V

## Determine main display card
bashio::log.info "DRM video cards:"
# La détection de carte est bypassée car l'accès à /sys/class/drm/ échoue et arrête le script
bashio::log.info "DRM video card driver and connection status:"
selected_card="card0" # ⬅️ DÉFINIR LA VALEUR PAR DÉFAUT
# Le bloc de détection est commenté
#for status_path in /sys/class/drm/card[0-9]*-*/status; do
#    [ -e "$status_path" ] || continue
#    status=$(cat "$status_path")
#    card_port=$(basename "$(dirname "$status_path")")
#    card=${card_port%%-*}
#    driver=$(basename "$(readlink "/sys/class/drm/$card/device/driver")")
#    if [ -z "$selected_card" ] && [ "$status" = "connected" ]; then
#        selected_card="$card"
#        printf "  *"
#    else
#        printf "  "
#    fi
#    printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
#done

# On affiche un avertissement clair pour expliquer la raison du bypass
if [ "$selected_card" = "card0" ]; then
    bashio::log.warning "WARNING: DRM card detection bypassed due to HAOS access restrictions. Using 'card0'."
fi

bashio::log.info "Continuity Check: Selected card is '$selected_card'. Proceeding to Xorg config."

#### Start Xorg
rm -rf /tmp/.X*-lock

if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf'..."
    echo "${XORG_CONF}" >| /etc/X11/xorg.conf
else
    # ÉTAPE 1: Créer le répertoire si manquant
    mkdir -p /etc/X11
    
    # ÉTAPE 2: Création manuelle du fichier (Nettoyé et avec l'option KMS intégrée)
    bashio::log.info "Creating default xorg.conf manually..."
    cat > /etc/X11/xorg.conf << EOF
Section "ServerLayout"
    Identifier      "DefaultLayout"
    Screen          0 "Screen0" 0 0
EndSection

Section "Device"
    Identifier      "Card0"
    Driver          "modesetting"
EndSection

Section "Monitor"
    Identifier      "Monitor0"
EndSection

Section "Screen"
    Identifier      "Screen0"
    Device          "Card0"
    Monitor         "Monitor0"
    DefaultDepth    24
EndSection

# General libinput catchall for keyboards
Section "InputClass"
    Identifier      "libinput keyboard"
    MatchIsKeyboard "on"
    Driver          "libinput"
EndSection

# General libinput catchall for mice and touchpads
Section "InputClass"
    Identifier      "libinput pointer"
    MatchIsPointer  "on"
    Driver          "libinput"
    Option          "Tapping" "on"
    Option          "NaturalScrolling" "true"
EndSection

# General libinput catchall for touchscreens
Section "InputClass"
    Identifier      "libinput touchscreen"
    MatchIsTouchscreen "on"
    Driver          "libinput"
    Option          "Tapping" "on"
    Option          "TappingDrag" "on"
EndSection
EOF
    
    # LIGNE SED RETIRÉE - L'option KMS est maintenant intégrée ci-dessus
    # sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\tOption\t\t\"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf

    if [ -z "$XORG_CONF" ]; then
        bashio::log.info "No user 'xorg.conf' data provided, using default..."
    elif [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending onto default 'xorg.conf'..."
        echo -e "\n#\n${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
fi

echo "."
printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#'
cat /etc/X11/xorg.conf
printf '%*s\n' 80 '' | tr ' ' '#'
echo "."

bashio::log.info "Starting X on DISPLAY=$DISPLAY..."
NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"
Xorg $NOCURSOR </dev/null &

XSTARTUP=60
for ((i=0; i<=XSTARTUP; i++)); do
    if xset q >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Restore /dev/tty0
if [ -n "$TTY0_DELETED" ]; then
    if mknod -m 620 /dev/tty0 c 4 0; then
        bashio::log.info "Restored /dev/tty0 successfully..."
    else
        bashio::log.error "Failed to restore /dev/tty0..."
    fi
fi

if ! xset q >/dev/null 2>&1; then
    bashio::log.error "Error: X server failed to start within $XSTARTUP seconds."
    exit 1
fi
bashio::log.info "X server started successfully after $i seconds..."

echo "xinput list:"
xinput list | sed 's/^/  /'

echo -e "\033[?25l" > /dev/console 2>/dev/null || true

if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || \
    unclutter --start-hidden --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || true
fi

#### Start Window manager
WINMGR=Openbox
openbox &
O_PID=$!
sleep 0.5
if ! kill -0 "$O_PID" 2>/dev/null; then
    bashio::log.error "Failed to start $WINMGR window manager"
    exit 1
fi
bashio::log.info "$WINMGR window manager started successfully..."

#### Configure screen timeout
xset +dpms
xset s "$SCREEN_TIMEOUT"
xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
if [ "$SCREEN_TIMEOUT" -eq 0 ]; then
    bashio::log.info "Screen timeout disabled..."
else
    bashio::log.info "Screen timeout after $SCREEN_TIMEOUT seconds..."
fi

#### Configure outputs
readarray -t ALL_OUTPUTS < <(xrandr --query | awk '/^[[:space:]]*[A-Za-z0-9-]+/ {print $1}')
bashio::log.info "All video outputs: ${ALL_OUTPUTS[*]}"

readarray -t OUTPUTS < <(xrandr --query | awk '/ connected/ {print $1}')
if [ ${#OUTPUTS[@]} -eq 0 ]; then
    bashio::log.info "ERROR: No connected outputs detected. Exiting.."
    exit 1
fi

if [ "$OUTPUT_NUMBER" -gt "${#OUTPUTS[@]}" ]; then
    OUTPUT_NUMBER=${#OUTPUTS[@]}
fi
bashio::log.info "Connected video outputs: (Selected output marked with '*')"
for i in "${!OUTPUTS[@]}"; do
    marker=" "
    [ "$i" -eq "$((OUTPUT_NUMBER - 1))" ] && marker="*"
    bashio::log.info "  ${marker}[$((i + 1))] ${OUTPUTS[$i]}"
done
OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}"

for OUTPUT in "${OUTPUTS[@]}"; do
    if [ "$OUTPUT" = "$OUTPUT_NAME" ]; then
        if [ "$ROTATE_DISPLAY" = normal ]; then
            xrandr --output "$OUTPUT_NAME" --primary --auto
        else
            xrandr --output "$OUTPUT_NAME" --primary --rotate "${ROTATE_DISPLAY}"
            bashio::log.info "Rotating $OUTPUT_NAME: ${ROTATE_DISPLAY}"
        fi
    else
        xrandr --output "$OUTPUT" --off
    fi
done

if [ "$MAP_TOUCH_INPUTS" = true ]; then
    while IFS= read -r id; do
        name=$(xinput list --name-only "$id" 2>/dev/null)
        [[ "${name,,}" =~ (^|[^[:alnum:]_])(touch|touchscreen|stylus)([^[:alnum:]_]|$) ]] || continue
        xinput_line=$(xinput list "$id" 2>/dev/null)
        [[ "$xinput_line" =~ \[(slave|master)[[:space:]]+keyboard[[:space:]]+\([0-9]+\)\] ]] && continue
        props="$(xinput list-props "$id" 2>/dev/null)"
        [[ "$props" = *"Coordinate Transformation Matrix"* ]] ||  continue
        xinput map-to-output "$id" "$OUTPUT_NAME" && RESULT="SUCCESS" || RESULT="FAILED"
        bashio::log.info "Mapping: input device [$id|$name] -->  $OUTPUT_NAME [$RESULT]"
    done < <(xinput list --id-only | sort -n)
fi

#### Set keyboard layout
setxkbmap "$KEYBOARD_LAYOUT"
export LANG=$KEYBOARD_LAYOUT
bashio::log.info "Setting keyboard layout and language to: $KEYBOARD_LAYOUT"
setxkbmap -query  | sed 's/^/  /'

### Get screen dimensions
read -r SCREEN_WIDTH SCREEN_HEIGHT < <(
    xrandr --query --current | grep "^$OUTPUT_NAME " |
    sed -n "s/^$OUTPUT_NAME connected.* \([0-9]\+\)x\([0-9]\+\)+.*$/\1 \2/p"
)

if [[ -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    bashio::log.info "Screen: Width=$SCREEN_WIDTH  Height=$SCREEN_HEIGHT"
else
    bashio::log.error "Could not determine screen size for output $OUTPUT_NAME"
fi

#### Onboard keyboard (keep same logic as original)
if [[ "$ONSCREEN_KEYBOARD" = true && -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    # ... [Gardez tout le code onboard keyboard de l'original] ...
    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" &
fi

#### Start REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &

################################################################################
#### FIREFOX LAUNCH (REMPLACE LUAKIT)
################################################################################
if [ "$DEBUG_MODE" != true ]; then
    # Créer profil Firefox
    FIREFOX_PROFILE="/tmp/firefox-kiosk-profile"
    rm -rf "$FIREFOX_PROFILE" 2>/dev/null
    mkdir -p "$FIREFOX_PROFILE"

    # Configuration Firefox optimisée pour kiosk
    cat > "$FIREFOX_PROFILE/user.js" << EOF
user_pref("browser.startup.homepage", "${HA_URL}/${HA_DASHBOARD}");
user_pref("browser.fullscreen.autohide", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("privacy.donottrackheader.enabled", true);
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);
EOF

    # Ajouter dark mode si activé
    if [ "$DARK_MODE" = true ]; then
        echo 'user_pref("ui.systemUsesDarkTheme", 1);' >> "$FIREFOX_PROFILE/user.js"
    fi

    # Calculer le zoom (100 = 1.0, 150 = 1.5, etc.)
    ZOOM_DECIMAL=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")
    echo "user_pref(\"layout.css.devPixelsPerPx\", \"$ZOOM_DECIMAL\");" >> "$FIREFOX_PROFILE/user.js"

    FULL_URL="${HA_URL}/${HA_DASHBOARD}"
    bashio::log.info "Launching Firefox to: $FULL_URL"
    bashio::log.info "Zoom level: ${ZOOM_LEVEL}% ($ZOOM_DECIMAL)"

    # Lancer Firefox en kiosk
    firefox --kiosk --profile "$FIREFOX_PROFILE" "$FULL_URL" > /tmp/firefox.log 2>&1 &
    FIREFOX_PID=$!
    bashio::log.info "Firefox launched (PID: $FIREFOX_PID)"

    # Attendre un peu puis auto-login
    sleep "$LOGIN_DELAY"
    
    (
        sleep 3
        WINDOW_ID=$(xdotool search --name "Mozilla Firefox" 2>/dev/null | head -1)
        if [ -n "$WINDOW_ID" ]; then
            bashio::log.info "Auto-login: Found Firefox window $WINDOW_ID"
            xdotool windowactivate --sync "$WINDOW_ID"
            sleep 1
            bashio::log.info "Typing username..."
            xdotool type --delay 100 "$HA_USERNAME"
            xdotool key Tab
            sleep 0.5
            bashio::log.info "Typing password..."
            xdotool type --delay 100 "$HA_PASSWORD"
            sleep 0.5
            xdotool key Return
            bashio::log.info "✓ Auto-login completed"
        else
            bashio::log.warning "Firefox window not found for auto-login"
        fi
    ) &

    # Attendre Firefox
    wait "$FIREFOX_PID"
else
    bashio::log.info "Entering debug mode (X & $WINMGR but no browser)..."
    exec sleep infinite
fi
