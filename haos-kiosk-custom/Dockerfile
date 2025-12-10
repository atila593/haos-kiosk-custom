ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk update && apk add --no-cache \
        xorg-server \
        xf86-video-intel \
        xf86-video-fbdev \
        xf86-video-modesetting \
        xf86-input-libinput \
        xinput \
        dbus \
        ttf-freefont \
        openbox \           <-- Gestionnaire de fenêtres
        xset \              <-- Utilitaire Xorg (économiseur d'écran)
        xrandr \            <-- Utilitaire Xorg (rotation/résolution)
        setxkbmap \         <-- Utilitaire Xorg (configuration clavier)
        xkeyboard-config \  <-- Base de données de configuration clavier
        firefox-esr \
        py3-pip \
        python3 \
        bash \
        patch \
        eudev \
        util-linux \
        procps \
        tini
RUN rm -rf /usr/share/luakit || true \
    && rm -rf /root/.config/luakit || true

# Copy scripts (keyboard, rest server, launcher)
COPY toggle_keyboard.py rest_server.py /
RUN pip install --no-cache-dir --break-system-packages aiohttp

# Installer ton run.sh
COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]

