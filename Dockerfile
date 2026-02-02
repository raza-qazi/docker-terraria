FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

ARG VERSION="1453"
LABEL maintainer="your-email@example.com"


RUN \
 apt-get update && \
 apt-get install -y unzip curl && \
 mkdir -p /defaults && \
 echo "{}" > /defaults/favorites.json && \
 mkdir -p /app/terraria && \
 curl -L -o /tmp/terraria.zip \
    "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${VERSION}.zip" && \
 unzip /tmp/terraria.zip "${VERSION}/Linux/*" -d /tmp/terraria && \
 mv /tmp/terraria/${VERSION}/Linux/* /app/terraria/ && \
 chmod +x /app/terraria/TerrariaServer.bin.x86_64 && \
 apt-get clean && \
 rm -rf /tmp/* /var/tmp/*

# Create wrapper script
RUN cat > /app/terraria/wrapper.sh <<'EOF'
#!/bin/bash
SERVER_BIN="/app/terraria/TerrariaServer.bin.x86_64"
echo "Starting Terraria Server..."

shutdown_server() {
    echo "Shutdown signal received, saving world..."
    echo "exit" >&3
    wait $SERVER_PID
    echo "Server stopped"
    exit 0
}

trap 'shutdown_server' SIGTERM SIGINT

$SERVER_BIN -config /config/serverconfig.txt -worldpath /world -logpath /world <&3 &
SERVER_PID=$!
exec 3>&1
wait $SERVER_PID
EOF

# Create s6 service
RUN mkdir -p /etc/services.d/terraria && \
    cat > /etc/services.d/terraria/run <<'EOF'
#!/usr/bin/with-contenv bash
cd /app/terraria
exec s6-setuidgid abc /app/terraria/wrapper.sh
EOF

# Set all permissions
RUN chmod +x /app/terraria/wrapper.sh && \
    chmod +x /etc/services.d/terraria/run

COPY root/ /

# Fix permissions on copied files
RUN chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world", "/config"]