ARG BUILD_FROM
FROM $BUILD_FROM

# Install firefox and necessary dependencies
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-intel \
    xf86-video-fbdev \
    dbus \
    ttf-freefont \
    firefox-esr \
    py3-pip \
    python3 \
    bash \
    patch \
    # Tools for debugging
    procps \
    tini

# Clean old Luakit files if present (optional safety)
RUN rm -rf /usr/share/luakit || true \
    && rm -rf /root/.config/luakit || true

# Copy scripts (keyboard, rest server, launcher)
COPY toggle_keyboard.py rest_server.py /
RUN pip install --no-cache-dir --break-system-packages aiohttp

# Installer ton run.sh
COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]

