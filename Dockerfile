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

# Create wrapper script with named pipe
RUN cat > /app/terraria/wrapper.sh <<'EOF'
#!/bin/bash
SERVER_BIN="/app/terraria/TerrariaServer.bin.x86_64"
PIPE="/tmp/terraria-input"

echo "Starting Terraria Server..."

# Create named pipe
rm -f "$PIPE"
mkfifo "$PIPE"

shutdown_server() {
    echo "Shutdown signal received, saving world..."
    echo "exit" > "$PIPE"
    sleep 2
    wait $SERVER_PID 2>/dev/null
    rm -f "$PIPE"
    echo "Server stopped"
    exit 0
}

trap 'shutdown_server' SIGTERM SIGINT

# Keep pipe open in background
tail -f "$PIPE" &
TAIL_PID=$!

# Start server
$SERVER_BIN -config /config/serverconfig.txt -worldpath /world -logpath /world < "$PIPE" &
SERVER_PID=$!

# Wait for server
wait $SERVER_PID
EXIT_CODE=$?

# Cleanup
kill $TAIL_PID 2>/dev/null
rm -f "$PIPE"

exit $EXIT_CODE
EOF

# Create s6 service
RUN mkdir -p /etc/services.d/terraria && \
    cat > /etc/services.d/terraria/run <<'EOF'
#!/usr/bin/with-contenv bash
cd /app/terraria
exec s6-setuidgid abc /app/terraria/wrapper.sh
EOF

# Set permissions
RUN chmod +x /app/terraria/wrapper.sh && \
    chmod +x /etc/services.d/terraria/run

COPY root/ /

RUN chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world", "/config"]