# 1. Image de base
ARG BUILD_FROM
FROM $BUILD_FROM

# 2. Installation des paquets système ET Python (Alpine Linux)
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
    py3-aiohttp \
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

# 3. Répertoire de travail
WORKDIR /app

# 4. Copie des fichiers
COPY run.sh /app/
COPY rest_server.py /app/

# 5. Permissions
RUN chmod a+x /app/run.sh

# 6. Lancement
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/run.sh"]
