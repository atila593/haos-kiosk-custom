#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.1-chromium-autologin-fixed"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
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
    bashio::log.warning "Warning: HA_USERNAME and HA_PASSWORD not set, auto-login disabled"
    AUTO_LOGIN=false
else
    AUTO_LOGIN=true
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
    mount -o remount,rw /dev || true
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

## Determine main display card
bashio::log.info "DRM video cards:"
bashio::log.info "DRM video card driver and connection status:"
selected_card="card0"

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
    mkdir -p /etc/X11
    
    bashio::log.info "Creating default xorg.conf manually..."
    cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "modesetting"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
EndSection
EOF

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

bashio::log.info "Waiting 5 seconds for X to initialize..."
sleep 5

bashio::log.info "X initialization complete, continuing..."
export DISPLAY=:0

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

#### Onboard keyboard - DISABLED (not installed in this container)
if [[ "$ONSCREEN_KEYBOARD" = true ]]; then
    bashio::log.warning "Onboard keyboard requested but not available in this container version"
    bashio::log.warning "Virtual keyboard functionality is not supported"
fi

#### Start REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &

################################################################################
#### CRÉER UN SCRIPT JS POUR FERMER LA SIDEBAR AU DÉMARRAGE
################################################################################

if [ "$HA_SIDEBAR" = "none" ]; then
    bashio::log.info "Creating sidebar auto-close script..."
    
    cat > /tmp/close-sidebar.js << 'JSEOF'
(function() {
    console.log('[HAOSKiosk] Auto-close sidebar script loaded');
    
    function closeSidebar() {
        // Attendre que Home Assistant soit chargé
        const checkInterval = setInterval(() => {
            const homeAssistant = document.querySelector('home-assistant');
            if (homeAssistant && homeAssistant.shadowRoot) {
                const drawer = homeAssistant.shadowRoot.querySelector('ha-drawer');
                if (drawer && drawer.shadowRoot) {
                    const mdcDrawer = drawer.shadowRoot.querySelector('mwc-drawer');
                    if (mdcDrawer && mdcDrawer.open) {
                        console.log('[HAOSKiosk] Closing sidebar...');
                        mdcDrawer.open = false;
                        clearInterval(checkInterval);
                    }
                }
            }
        }, 500);
        
        // Arrêter après 30 secondes max
        setTimeout(() => clearInterval(checkInterval), 30000);
    }
    
    // Lancer après le chargement de la page
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', closeSidebar);
    } else {
        closeSidebar();
    }
})();
JSEOF
    
    bashio::log.info "Sidebar auto-close script created"
fi

if [ "$AUTO_LOGIN" = true ]; then
    bashio::log.info "Setting up auto-login userscript..."
    
    # Échapper les caractères spéciaux pour JavaScript
    HA_USERNAME_ESC=$(echo "$HA_USERNAME" | sed "s/'/\\\'/g" | sed 's/"/\\"/g')
    HA_PASSWORD_ESC=$(echo "$HA_PASSWORD" | sed "s/'/\\\'/g" | sed 's/"/\\"/g')
    HA_URL_BASE=$(echo "$HA_URL" | sed 's|/*$||')
    
    # Créer le userscript
    cat > /tmp/autologin.js << 'JSEOF'
(function() {
    console.log('[HAOSKiosk] Userscript loaded at', new Date().toISOString());
    
    const config = {
        username: '__USERNAME__',
        password: '__PASSWORD__',
        haUrlBase: '__HA_URL_BASE__',
        loginDelay: __LOGIN_DELAY__,
        sidebar: '__HA_SIDEBAR__'
    };
    
    function attemptLogin() {
        console.log('[HAOSKiosk] Attempting login...');
        
        const username = document.querySelector('input[name="username"], input[autocomplete="username"], input[type="text"]');
        const password = document.querySelector('input[name="password"], input[autocomplete="current-password"], input[type="password"]');
        const submit = document.querySelector('button[type="submit"], mwc-button, paper-button');
        
        console.log('[HAOSKiosk] Found elements:', {
            username: !!username,
            password: !!password,
            submit: !!submit
        });
        
        if (username && password && submit) {
            username.value = config.username;
            username.dispatchEvent(new Event('input', {bubbles: true}));
            username.dispatchEvent(new Event('change', {bubbles: true}));
            
            password.value = config.password;
            password.dispatchEvent(new Event('input', {bubbles: true}));
            password.dispatchEvent(new Event('change', {bubbles: true}));
            
            setTimeout(() => {
                console.log('[HAOSKiosk] Clicking submit button');
                submit.click();
            }, 500);
            
            return true;
        }
        return false;
    }
    
    function checkAndLogin() {
        const isAuthPage = window.location.href.includes('/auth/');
        const hasLoginForm = document.querySelector('input[type="password"]') !== null;
        
        console.log('[HAOSKiosk] Check:', {isAuthPage, hasLoginForm});
        
        if (isAuthPage || hasLoginForm) {
            setTimeout(() => {
                if (!attemptLogin()) {
                    console.log('[HAOSKiosk] Login failed, will retry...');
                    setTimeout(checkAndLogin, 2000);
                }
            }, config.loginDelay * 1000);
        }
    }
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', checkAndLogin);
    } else {
        checkAndLogin();
    }
    
    const observer = new MutationObserver(() => {
        if (document.querySelector('input[type="password"]') && !window.loginAttempted) {
            window.loginAttempted = true;
            checkAndLogin();
        }
    });
    
    observer.observe(document.body, {childList: true, subtree: true});
})();
JSEOF
    
    # Remplacer les placeholders
    sed -i "s|__USERNAME__|${HA_USERNAME_ESC}|g" /tmp/autologin.js
    sed -i "s|__PASSWORD__|${HA_PASSWORD_ESC}|g" /tmp/autologin.js
    sed -i "s|__HA_URL_BASE__|${HA_URL_BASE}|g" /tmp/autologin.js
    sed -i "s|__LOGIN_DELAY__|${LOGIN_DELAY}|g" /tmp/autologin.js
    sed -i "s|__HA_SIDEBAR__|${HA_SIDEBAR}|g" /tmp/autologin.js
    
    bashio::log.info "Auto-login userscript created"
fi

################################################################################
#### CRÉER CSS POUR FORCER L'AFFICHAGE DU MENU HAMBURGER (SUPPRIMÉ - NON NÉCESSAIRE)
################################################################################

# Le CSS n'est plus nécessaire car le menu hamburger est visible par défaut
# en mode --start-fullscreen (au lieu de --kiosk)

################################################################################
#### CHROMIUM LAUNCH
################################################################################

# Calculer le zoom/DPI
ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")

# Créer le profil utilisateur Chromium
mkdir -p /tmp/chromium-profile

# Construire les flags Chromium - CHANGEMENT IMPORTANT: --start-fullscreen au lieu de --kiosk
CHROME_FLAGS="\
    --no-sandbox \
    --enable-features=WebUIDisableNewBadgeStyle \
    --disable-gpu \
    --disable-software-rasterizer \
    --start-fullscreen \
    --disable-infobars \
    --force-device-scale-factor=$ZOOM_DPI \
    --disable-features=TranslateUI,ImprovedEmailValidation \
    --window-size=$SCREEN_WIDTH,$SCREEN_HEIGHT \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile \
    --user-stylesheet=/tmp/force-sidebar.css"

# Dark mode
[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

# Construire l'URL complète
FULL_URL="${HA_URL}"
if [ -n "$HA_DASHBOARD" ]; then
    FULL_URL="${HA_URL}/${HA_DASHBOARD}"
    
    # NE PAS ajouter hide_sidebar dans l'URL si on veut voir le hamburger
    # On laisse le CSS forcer l'affichage à la place
    if [ "$HA_SIDEBAR" = "none" ]; then
        bashio::log.info "Sidebar configured as 'none' but will be accessible via hamburger menu"
    fi
fi

bashio::log.info "Launching Chromium to: $FULL_URL"
bashio::log.info "Zoom level: ${ZOOM_LEVEL}% ($ZOOM_DPI)"
bashio::log.info "Mode: Fullscreen (hamburger menu visible)"
bashio::log.info "Auto-login: $([ "$AUTO_LOGIN" = true ] && echo "ENABLED" || echo "DISABLED (using trusted networks)")"
[ "$DEBUG_MODE" = true ] && bashio::log.info "Launch flags: $CHROME_FLAGS"

# Lancer Chromium
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!
bashio::log.info "Chromium launched (PID: $CHROME_PID)"

# Si auto-login activé, utiliser xdotool
if [ "$AUTO_LOGIN" = true ]; then
    (
        # Attendre que la page soit chargée et redirigée vers /auth/authorize
        # Convertir LOGIN_DELAY en entier pour l'arithmétique bash
        LOGIN_DELAY_INT=${LOGIN_DELAY%.*}
        TOTAL_WAIT=$((LOGIN_DELAY_INT + 3))
        bashio::log.info "Waiting ${TOTAL_WAIT}s for OAuth redirect and login page..."
        sleep $TOTAL_WAIT
        
        # Trouver la fenêtre Chromium
        for attempt in {1..10}; do
            WINDOW_ID=$(xdotool search --class chromium 2>/dev/null | head -1)
            [ -n "$WINDOW_ID" ] && break
            bashio::log.info "Attempt $attempt: Waiting for Chromium window..."
            sleep 1
        done
        
        if [ -z "$WINDOW_ID" ]; then
            bashio::log.error "Could not find Chromium window for auto-login"
            exit 0
        fi
        
        bashio::log.info "Found Chromium window: $WINDOW_ID"
        
        # Activer la fenêtre
        xdotool windowactivate --sync "$WINDOW_ID"
        sleep 2
        
        bashio::log.info "Starting auto-login sequence..."
        
        # Cliquer vers le haut de l'écran où se trouve généralement le formulaire
        xdotool mousemove --window "$WINDOW_ID" 960 350
        xdotool click 1
        sleep 1
        
        # Cliquer spécifiquement sur la zone du champ username (approximativement)
        xdotool mousemove --window "$WINDOW_ID" 960 420
        xdotool click 1
        sleep 1
        
        # Taper le username
        bashio::log.info "Typing username: $HA_USERNAME"
        xdotool type --clearmodifiers --delay 120 "$HA_USERNAME"
        sleep 1
        
        # Tab vers le champ password
        xdotool key Tab
        sleep 1
        
        # Taper le password
        bashio::log.info "Typing password..."
        xdotool type --clearmodifiers --delay 120 "$HA_PASSWORD"
        sleep 1
        
        # Soumettre le formulaire avec Enter
        bashio::log.info "Submitting login form..."
        xdotool key Return
        
        bashio::log.info "✓ Auto-login sequence completed"
        
    ) &
fi

# Afficher les logs Chromium en mode debug
if [ "$DEBUG_MODE" = true ]; then
    tail -f /tmp/chromium.log &
fi

wait "$CHROME_PID"
