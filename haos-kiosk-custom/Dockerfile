# 1. Image de base Home Assistant (gérée par le build system)
ARG BUILD_FROM
FROM $BUILD_FROM

# 2. Installation des paquets système (Alpine Linux)
# On regroupe tout pour optimiser les couches Docker
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-intel \
    xf86-video-fbdev \
    xf86-video-modesetting \
    xf86-input-libinput \
    xf86-input-evdev \
    xinput \
    dbus \
    ttf-freefont \
    openbox \
    xset \
    xrandr \
    setxkbmap \
    xkeyboard-config \
    chromium \
    python3 \
    py3-pip \
    bash \
    patch \
    eudev \
    util-linux \
    procps \
    tini \
    matchbox-keyboard \
    libpng \
    xdotool \
    && rm -rf /tmp/* /var/cache/apk/*

# 3. Installation des dépendances Python pour ton serveur REST
# On le fait avant de copier le code pour profiter du cache Docker
RUN pip3 install --no-cache-dir aiohttp

# 4. Définition du répertoire de travail
WORKDIR /app

# 5. Copie des fichiers de ton addon
# Assure-toi que ces fichiers sont dans le même dossier que ton Dockerfile
COPY run.sh /app/
COPY rest_server.py /app/
# Si tu as d'autres scripts (ex: toggle_keyboard.py), décommente la ligne suivante :
# COPY *.py /app/

# 6. Permissions d'exécution sur le script de démarrage
RUN chmod a+x /app/run.sh

# 7. Utilisation de Tini pour gérer les processus correctement
ENTRYPOINT ["/sbin/tini", "--"]

# 8. Commande de lancement
CMD ["/app/run.sh"]
