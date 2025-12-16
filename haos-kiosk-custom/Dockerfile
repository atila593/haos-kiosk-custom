ARG BUILD_FROM
FROM $BUILD_FROM

# 1. Installer tous les paquets (sur une seule ligne pour éviter les erreurs de parsing)
RUN apk update && apk add --no-cache xorg-server xf86-video-intel xf86-video-fbdev xf86-video-modesetting xf86-input-libinput xinput dbus ttf-freefont openbox xset xrandr setxkbmap xkeyboard-config chromium py3-pip python3 bash patch eudev util-linux procps tini onboard py3-tk

# 2. Nettoyer l'ancien navigateur (Luakit)
RUN rm -rf /usr/share/luakit || true

# 3. Copier les scripts nécessaires (y compris rest_server.py)
COPY toggle_keyboard.py rest_server.py /

# 4. Installer les dépendances Python (attention, pas de '\' à la fin du RUN ci-dessus)
RUN pip3 install --no-cache-dir --break-system-packages aiohttp

# 5. Installer le run.sh
COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
