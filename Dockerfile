FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

ARG version="1453"
LABEL maintainer="your-email@example.com"

RUN \
 echo "**** install terraria ****" && \
 apt-get update && \
 apt-get install -y unzip curl && \
 mkdir -p /root/.local/share/Terraria && \
 echo "{}" > /root/.local/share/Terraria/favorites.json && \
 mkdir -p /app/terraria/bin && \
 curl -L -o /tmp/terraria.zip "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip" && \
 unzip /tmp/terraria.zip ${version}'/Linux/*' -d /tmp/terraria && \
 mv /tmp/terraria/${version}/Linux/* /app/terraria/bin && \
 echo "**** creating user ****" && \
 mkdir -p /config && \
 useradd -u 911 -U -d /config -s /bin/false -G users terraria && \
 echo "**** cleanup ****" && \
 apt-get clean && \
 rm -rf \
    /tmp/* \
    /var/tmp/*

COPY root/ /

EXPOSE 7777
VOLUME ["/world","/config"]

ENTRYPOINT ["/init"]
CMD ["s6-setuidgid", "terraria", "/app/terraria/bin/TerrariaServer.bin.x86_64", "-config", "/config/serverconfig.txt"]