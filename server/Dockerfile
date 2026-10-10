# Skyloop game server: the project run by headless Godot, serving WebSocket on 8910.
# Build from the repo root:  docker build -f server/Dockerfile -t skyloop-server .
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /opt/godot \
 && mv /opt/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /opt/godot \
 && apt-get purge -y wget unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# The server only needs the rules, the service and its scene; the art stays out of the image.
COPY project.godot ./
COPY core ./core
COPY net ./net
COPY server ./server
# project.godot autoloads Fx (sound) and Net; they are tiny and keep startup identical to the app.
COPY ui/fx.gd ./ui/fx.gd
COPY audio ./audio
COPY icon.png ./
COPY art/ui/splash.png ./art/ui/splash.png
RUN godot --headless --path /app --import || true

ENV SKYLOOP_PORT=8910 \
    SKYLOOP_DATA=/data
VOLUME /data
EXPOSE 8910
CMD ["godot", "--headless", "--path", "/app", "res://server/server.tscn"]
