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
    openbox \
    xset \
    xrandr \
    setxkbmap \
    xkeyboard-config \
    chromium \           # Navigateur (ligne 18)
    py3-pip \            # Dépendance de Python (ligne 19)
    python3 \
    bash \
    patch \
    eudev \
    util-linux \
    procps \
    tini                 # Dernière dépendance SANS '\'
    
RUN rm -rf /usr/share/luakit || true \

# Copy scripts (keyboard, rest server, launcher)
COPY toggle_keyboard.py rest_server.py /
# Attention : pip est pour Python 3, donc utilisez 'pip3' sur Alpine.
RUN pip3 install --no-cache-dir --break-system-packages aiohttp

# Installer ton run.sh
COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
