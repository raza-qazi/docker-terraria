FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

ARG version="1453"
LABEL maintainer="your-email@example.com"

RUN \
 apt-get update && \
 apt-get install -y unzip curl && \
 mkdir -p /root/.local/share/Terraria && \
 echo "{}" > /root/.local/share/Terraria/favorites.json && \
 mkdir -p /app/terraria/bin && \
 curl -L -o /tmp/terraria.zip "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip" && \
 unzip /tmp/terraria.zip ${version}'/Linux/*' -d /tmp/terraria && \
 mv /tmp/terraria/${version}/Linux/* /app/terraria/bin && \
 mkdir -p /config && \
 useradd -U -d /config -s /bin/false -G users terraria && \
 chmod +x /app/terraria/bin/TerrariaServer.bin.x86_64 && \
 chown -R terraria:terraria /app/terraria && \
 apt-get clean && \
 rm -rf \
    /tmp/* \
    /var/tmp/*

COPY root/ /

RUN sed -i 's|#!/usr/bin/with-contenv bash|#!/bin/bash|g' /etc/cont-init.d/30-config && \
    chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world","/config"]

ENTRYPOINT ["/init"]
CMD ["s6-setuidgid", "terraria", "/app/terraria/bin/TerrariaServer.bin.x86_64", "-config", "/config/serverconfig.txt", "-worldpath", "/world", "-logpath", "/world"]