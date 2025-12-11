#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.1-chromium-autologin"

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

#### Onboard keyboard
if [[ "$ONSCREEN_KEYBOARD" = true && -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" &
fi

#### Start REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &

################################################################################
#### CRÉER L'EXTENSION CHROMIUM POUR AUTO-LOGIN
################################################################################

if [ "$AUTO_LOGIN" = true ]; then
    bashio::log.info "Setting up auto-login extension..."
    
    # Créer le répertoire de l'extension
    mkdir -p /tmp/chromium-extension
    
    # Échapper les caractères spéciaux pour JavaScript
    HA_USERNAME_ESC=$(echo "$HA_USERNAME" | sed "s/'/\\\'/g")
    HA_PASSWORD_ESC=$(echo "$HA_PASSWORD" | sed "s/'/\\\'/g")
    HA_URL_BASE=$(echo "$HA_URL" | sed 's|/*$||')  # Enlever les slashes finaux
    
    # Créer le manifest de l'extension
    cat > /tmp/chromium-extension/manifest.json << 'MANIFESTEOF'
{
  "manifest_version": 3,
  "name": "HAOSKiosk Auto-Login",
  "version": "1.0",
  "description": "Auto-login pour Home Assistant",
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["autologin.js"],
      "run_at": "document_idle"
    }
  ],
  "host_permissions": ["<all_urls>"]
}
MANIFESTEOF
    
    # Créer le script d'auto-login
    cat > /tmp/chromium-extension/autologin.js << JSEOF
// HAOSKiosk Auto-Login Script
(function() {
    'use strict';
    
    const USERNAME = '${HA_USERNAME_ESC}';
    const PASSWORD = '${HA_PASSWORD_ESC}';
    const HA_URL_BASE = '${HA_URL_BASE}';
    const LOGIN_DELAY = ${LOGIN_DELAY};
    const SIDEBAR = '${HA_SIDEBAR}';
    
    console.log('[HAOSKiosk] Auto-login script loaded');
    console.log('[HAOSKiosk] Current URL:', window.location.href);
    
    // Fonction pour échapper les caractères spéciaux en regex
    function escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
    
    // Fonction pour tenter la connexion
    function attemptLogin() {
        console.log('[HAOSKiosk] Attempting login...');
        
        const usernameField = document.querySelector('input[autocomplete="username"]');
        const passwordField = document.querySelector('input[autocomplete="current-password"]');
        const haCheckbox = document.querySelector('ha-checkbox');
        const submitButton = document.querySelector('mwc-button[type="submit"], button[type="submit"], paper-button');
        
        console.log('[HAOSKiosk] Login elements:', {
            username: !!usernameField,
            password: !!passwordField,
            checkbox: !!haCheckbox,
            submit: !!submitButton
        });
        
        if (usernameField && passwordField && submitButton) {
            console.log('[HAOSKiosk] Filling login form...');
            
            // Remplir le username
            usernameField.value = USERNAME;
            usernameField.dispatchEvent(new Event('input', { bubbles: true }));
            usernameField.dispatchEvent(new Event('change', { bubbles: true }));
            
            // Remplir le password
            passwordField.value = PASSWORD;
            passwordField.dispatchEvent(new Event('input', { bubbles: true }));
            passwordField.dispatchEvent(new Event('change', { bubbles: true }));
            
            // Cocher "Se souvenir" si présent
            if (haCheckbox && !haCheckbox.hasAttribute('checked')) {
                console.log('[HAOSKiosk] Checking remember me checkbox...');
                haCheckbox.setAttribute('checked', '');
                haCheckbox.checked = true;
                haCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
            }
            
            // Soumettre après un court délai
            setTimeout(function() {
                console.log('[HAOSKiosk] Submitting login form...');
                submitButton.click();
            }, 1000);
            
            return true;
        }
        return false;
    }
    
    // Fonction pour appliquer les paramètres HA
    function applyHASettings() {
        try {
            console.log('[HAOSKiosk] Applying HA settings...');
            
            // Browser_mod ID
            localStorage.setItem('browser_mod-browser-id', 'haos_kiosk');
            
            // Sidebar visibility
            if (SIDEBAR && SIDEBAR !== 'none') {
                localStorage.setItem('dockedSidebar', SIDEBAR);
            } else {
                localStorage.removeItem('dockedSidebar');
            }
            
            console.log('[HAOSKiosk] Settings applied: sidebar=' + SIDEBAR);
        } catch (err) {
            console.error('[HAOSKiosk] Failed to apply settings:', err);
        }
    }
    
    // Vérifier si on est sur la page de login
    function isLoginPage() {
        const urlPattern = new RegExp('^' + escapeRegex(HA_URL_BASE) + '/auth/authorize\\?response_type=code');
        return urlPattern.test(window.location.href) || 
               document.querySelector('input[autocomplete="username"]') !== null;
    }
    
    // Vérifier si on est sur le dashboard
    function isDashboardPage() {
        const urlPattern = new RegExp('^' + escapeRegex(HA_URL_BASE) + '/(?!auth/)');
        return urlPattern.test(window.location.href) && 
               !window.location.href.includes('/auth/');
    }
    
    // Initialisation
    function init() {
        console.log('[HAOSKiosk] Initializing...');
        
        if (isLoginPage()) {
            console.log('[HAOSKiosk] Login page detected');
            setTimeout(attemptLogin, LOGIN_DELAY * 1000);
        } else if (isDashboardPage()) {
            console.log('[HAOSKiosk] Dashboard page detected');
            applyHASettings();
        }
    }
    
    // Attendre que la page soit chargée
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
    
    // Observer les changements pour détecter l'apparition du formulaire
    const observer = new MutationObserver(function(mutations) {
        if (isLoginPage() && !window.loginAttempted) {
            window.loginAttempted = true;
            console.log('[HAOSKiosk] Login form appeared via mutation');
            setTimeout(attemptLogin, 1000);
        }
    });
    
    observer.observe(document.body, {
        childList: true,
        subtree: true
    });
    
    console.log('[HAOSKiosk] Observer active');
})();
JSEOF
    
    bashio::log.info "Auto-login extension created successfully"
fi

################################################################################
#### CHROMIUM LAUNCH
################################################################################

# Calculer le zoom/DPI
ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")

# Créer le profil utilisateur Chromium
mkdir -p /tmp/chromium-profile

# Construire les flags Chromium
CHROME_FLAGS="\
    --no-sandbox \
    --disable-gpu \
    --disable-software-rasterizer \
    --kiosk \
    --disable-infobars \
    --force-device-scale-factor=$ZOOM_DPI \
    --disable-features=TranslateUI,ImprovedEmailValidation \
    --window-size=$SCREEN_WIDTH,$SCREEN_HEIGHT \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile"

# Ajouter l'extension si auto-login activé
if [ "$AUTO_LOGIN" = true ]; then
    CHROME_FLAGS="$CHROME_FLAGS --load-extension=/tmp/chromium-extension"
fi

# Dark mode
[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

# Construire l'URL complète
FULL_URL="${HA_URL}"
if [ -n "$HA_DASHBOARD" ]; then
    FULL_URL="${HA_URL}/${HA_DASHBOARD}"
fi

bashio::log.info "Launching Chromium to: $FULL_URL"
bashio::log.info "Zoom level: ${ZOOM_LEVEL}% ($ZOOM_DPI)"
bashio::log.info "Auto-login: $([ "$AUTO_LOGIN" = true ] && echo "ENABLED" || echo "DISABLED")"
[ "$DEBUG_MODE" = true ] && bashio::log.info "Launch flags: $CHROME_FLAGS"

# Lancer Chromium
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!
bashio::log.info "Chromium launched (PID: $CHROME_PID)"

# Afficher les logs Chromium en mode debug
if [ "$DEBUG_MODE" = true ]; then
    tail -f /tmp/chromium.log &
fi

wait "$CHROME_PID"
