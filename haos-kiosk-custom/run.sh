#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.5-chromium-sidebar-fix"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk (Chromium Edition) ########"
bashio::log.info "$(date) [Version: $VERSION]"

# ... [GARDER TOUT LE CODE JUSQU'À LA SECTION "CRÉER UN SCRIPT JS"]...

################################################################################
#### CRÉER LES USERSCRIPTS COMBINÉS
################################################################################

bashio::log.info "Creating combined userscript..."

# Échapper les caractères spéciaux pour JavaScript
HA_USERNAME_ESC=$(echo "$HA_USERNAME" | sed "s/'/\\\'/g" | sed 's/"/\\"/g')
HA_PASSWORD_ESC=$(echo "$HA_PASSWORD" | sed "s/'/\\\'/g" | sed 's/"/\\"/g')
HA_URL_BASE=$(echo "$HA_URL" | sed 's|/*$||')

# Créer le userscript combiné (auto-login + fermeture sidebar)
cat > /tmp/combined-userscript.js << 'JSEOF'
(function() {
    console.log('[HAOSKiosk] Combined userscript loaded at', new Date().toISOString());
    
    const config = {
        username: '__USERNAME__',
        password: '__PASSWORD__',
        haUrlBase: '__HA_URL_BASE__',
        loginDelay: __LOGIN_DELAY__,
        sidebar: '__HA_SIDEBAR__',
        autoLogin: __AUTO_LOGIN__
    };
    
    // ========== FONCTION AUTO-LOGIN ==========
    function attemptLogin() {
        if (!config.autoLogin) return false;
        
        console.log('[HAOSKiosk] Attempting auto-login...');
        
        const username = document.querySelector('input[name="username"], input[autocomplete="username"], input[type="text"]');
        const password = document.querySelector('input[name="password"], input[autocomplete="current-password"], input[type="password"]');
        const submit = document.querySelector('button[type="submit"], mwc-button, paper-button');
        
        if (username && password && submit) {
            console.log('[HAOSKiosk] Found login form elements');
            
            username.value = config.username;
            username.dispatchEvent(new Event('input', {bubbles: true}));
            username.dispatchEvent(new Event('change', {bubbles: true}));
            
            password.value = config.password;
            password.dispatchEvent(new Event('input', {bubbles: true}));
            password.dispatchEvent(new Event('change', {bubbles: true}));
            
            setTimeout(() => {
                console.log('[HAOSKiosk] Submitting login form');
                submit.click();
            }, 500);
            
            return true;
        }
        return false;
    }
    
    // ========== FONCTION FERMETURE SIDEBAR ==========
    function closeSidebar() {
        if (config.sidebar !== 'none') return;
        
        console.log('[HAOSKiosk] Attempting to close sidebar...');
        
        let attempts = 0;
        const maxAttempts = 60; // 30 secondes max
        
        const checkInterval = setInterval(() => {
            attempts++;
            
            const homeAssistant = document.querySelector('home-assistant');
            if (homeAssistant && homeAssistant.shadowRoot) {
                const drawer = homeAssistant.shadowRoot.querySelector('ha-drawer');
                if (drawer && drawer.shadowRoot) {
                    const mdcDrawer = drawer.shadowRoot.querySelector('mwc-drawer');
                    if (mdcDrawer) {
                        if (mdcDrawer.open) {
                            console.log('[HAOSKiosk] Closing sidebar now');
                            mdcDrawer.open = false;
                        }
                        clearInterval(checkInterval);
                        console.log('[HAOSKiosk] Sidebar control complete');
                        return;
                    }
                }
            }
            
            if (attempts >= maxAttempts) {
                console.log('[HAOSKiosk] Max attempts reached, stopping sidebar check');
                clearInterval(checkInterval);
            }
        }, 500);
    }
    
    // ========== FONCTION DE VÉRIFICATION ET LOGIN ==========
    function checkAndLogin() {
        const isAuthPage = window.location.href.includes('/auth/');
        const hasLoginForm = document.querySelector('input[type="password"]') !== null;
        
        if (config.autoLogin && (isAuthPage || hasLoginForm)) {
            console.log('[HAOSKiosk] Login page detected');
            setTimeout(() => {
                if (!attemptLogin()) {
                    console.log('[HAOSKiosk] Login attempt failed, will retry...');
                    setTimeout(checkAndLogin, 2000);
                }
            }, config.loginDelay * 1000);
        }
    }
    
    // ========== INITIALISATION ==========
    function init() {
        console.log('[HAOSKiosk] Initializing with config:', {
            autoLogin: config.autoLogin,
            sidebar: config.sidebar,
            currentUrl: window.location.href
        });
        
        // Démarrer la fermeture de sidebar dès que possible
        closeSidebar();
        
        // Gérer l'auto-login si activé
        if (config.autoLogin) {
            checkAndLogin();
            
            // Observer pour détecter l'apparition du formulaire de login
            const observer = new MutationObserver(() => {
                if (document.querySelector('input[type="password"]') && !window.loginAttempted) {
                    window.loginAttempted = true;
                    checkAndLogin();
                }
            });
            
            observer.observe(document.body, {childList: true, subtree: true});
        }
    }
    
    // Démarrer après le chargement de la page
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
JSEOF

# Remplacer les placeholders
sed -i "s|__USERNAME__|${HA_USERNAME_ESC}|g" /tmp/combined-userscript.js
sed -i "s|__PASSWORD__|${HA_PASSWORD_ESC}|g" /tmp/combined-userscript.js
sed -i "s|__HA_URL_BASE__|${HA_URL_BASE}|g" /tmp/combined-userscript.js
sed -i "s|__LOGIN_DELAY__|${LOGIN_DELAY}|g" /tmp/combined-userscript.js
sed -i "s|__HA_SIDEBAR__|${HA_SIDEBAR}|g" /tmp/combined-userscript.js
sed -i "s|__AUTO_LOGIN__|${AUTO_LOGIN}|g" /tmp/combined-userscript.js

bashio::log.info "Combined userscript created successfully"

################################################################################
#### CHROMIUM LAUNCH
################################################################################

# Calculer le zoom/DPI
ZOOM_DPI=$(awk "BEGIN {printf \"%.2f\", $ZOOM_LEVEL / 100}")

# Créer le profil utilisateur Chromium
mkdir -p /tmp/chromium-profile/Default

# Créer le fichier Preferences pour injecter le userscript
cat > /tmp/chromium-profile/Default/Preferences << PREFEOF
{
  "extensions": {
    "settings": {}
  }
}
PREFEOF

# Construire les flags Chromium
CHROME_FLAGS="\
    --no-sandbox \
    --disable-gpu \
    --disable-software-rasterizer \
    --start-fullscreen \
    --disable-infobars \
    --disable-notifications \
    --disable-popup-blocking \
    --force-device-scale-factor=$ZOOM_DPI \
    --disable-features=TranslateUI \
    --window-size=$SCREEN_WIDTH,$SCREEN_HEIGHT \
    --no-first-run \
    --user-data-dir=/tmp/chromium-profile \
    --load-and-launch-app=/tmp"

# Dark mode
[ "$DARK_MODE" = true ] && CHROME_FLAGS="$CHROME_FLAGS --force-dark-mode"

# Construire l'URL complète
FULL_URL="${HA_URL}"
if [ -n "$HA_DASHBOARD" ]; then
    FULL_URL="${HA_URL}/${HA_DASHBOARD}"
fi

# Créer un manifest.json pour le userscript
mkdir -p /tmp/userscript-extension
cat > /tmp/userscript-extension/manifest.json << MANIFEST
{
  "manifest_version": 2,
  "name": "HAOSKiosk Userscript",
  "version": "1.0",
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["userscript.js"],
      "run_at": "document_start"
    }
  ]
}
MANIFEST

cp /tmp/combined-userscript.js /tmp/userscript-extension/userscript.js

# Ajouter l'extension au lancement
CHROME_FLAGS="$CHROME_FLAGS --load-extension=/tmp/userscript-extension"

bashio::log.info "Launching Chromium to: $FULL_URL"
bashio::log.info "Zoom level: ${ZOOM_LEVEL}% ($ZOOM_DPI)"
bashio::log.info "Mode: Fullscreen with userscript injection"
bashio::log.info "Auto-login: $([ "$AUTO_LOGIN" = true ] && echo "ENABLED (JavaScript)" || echo "DISABLED")"
bashio::log.info "Sidebar: $HA_SIDEBAR"

# Lancer Chromium
chromium $CHROME_FLAGS "$FULL_URL" > /tmp/chromium.log 2>&1 &
CHROME_PID=$!
bashio::log.info "Chromium launched (PID: $CHROME_PID)"

# SUPPRIMER TOUTE LA SECTION xdotool AUTO-LOGIN - Elle n'est plus nécessaire

# Afficher les logs Chromium en mode debug
if [ "$DEBUG_MODE" = true ]; then
    tail -f /tmp/chromium.log &
fi

wait "$CHROME_PID"
