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

RUN echo '#!/bin/bash' > /app/terraria/run.sh && \
    echo 'PIPE=/tmp/terraria.fifo' >> /app/terraria/run.sh && \
    echo 'rm -f $PIPE && mkfifo $PIPE' >> /app/terraria/run.sh && \
    echo 'trap "echo exit > $PIPE" SIGTERM' >> /app/terraria/run.sh && \
    echo '# Forward console input to the pipe' >> /app/terraria/run.sh && \
    echo 'cat > $PIPE &' >> /app/terraria/run.sh && \
    echo '# Start Server reading from the pipe' >> /app/terraria/run.sh && \
    echo '/app/terraria/bin/TerrariaServer.bin.x86_64 -config /config/serverconfig.txt -worldpath /world -logpath /world < $PIPE &' >> /app/terraria/run.sh && \
    echo 'PID=$!' >> /app/terraria/run.sh && \
    echo 'wait $PID' >> /app/terraria/run.sh && \
    chmod +x /app/terraria/run.sh

COPY root/ /

RUN sed -i 's|#!/usr/bin/with-contenv bash|#!/bin/bash|g' /etc/cont-init.d/30-config && \
    chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world","/config"]

ENTRYPOINT ["/init"]

CMD ["s6-setuidgid", "terraria", "/app/terraria/run.sh"]