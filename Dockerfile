FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

ARG VERSION="1453"
LABEL maintainer="your-email@example.com"

# Install dependencies
RUN \
 echo "**** install packages ****" && \
 apt-get update && \
 apt-get install -y \
    unzip \
    curl \
    expect && \
 echo "**** install terraria ****" && \
 mkdir -p /defaults /app/terraria && \
 echo "{}" > /defaults/favorites.json && \
 curl -L -o /tmp/terraria.zip \
    "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${VERSION}.zip" && \
 unzip /tmp/terraria.zip "${VERSION}/Linux/*" -d /tmp/terraria && \
 mv /tmp/terraria/${VERSION}/Linux/* /app/terraria/ && \
 chmod +x /app/terraria/TerrariaServer.bin.x86_64 && \
 echo "**** cleanup ****" && \
 apt-get clean && \
 rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Create wrapper with proper pipe handling and unbuffered output
RUN cat > /app/terraria/wrapper.sh <<'WRAPPER_EOF'
#!/bin/bash
set -e

PIPE="/tmp/terraria-cmd"
SERVER_BIN="/app/terraria/TerrariaServer.bin.x86_64"

echo "==================================="
echo "Terraria Server Starting"
echo "==================================="

# Cleanup any old pipe
rm -f "$PIPE"
mkfifo "$PIPE"

# Shutdown handler
shutdown_server() {
    echo "==================================="
    echo "Shutdown signal received"
    echo "Sending exit command to server..."
    echo "==================================="
    
    echo "exit" > "$PIPE"
    
    # Wait up to 30 seconds for graceful shutdown
    local count=0
    while kill -0 $SERVER_PID 2>/dev/null && [ $count -lt 30 ]; do
        sleep 1
        count=$((count + 1))
    done
    
    # Force kill if still running
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "Force stopping server..."
        kill -9 $SERVER_PID 2>/dev/null
    fi
    
    rm -f "$PIPE"
    echo "Server stopped"
    exit 0
}

trap 'shutdown_server' SIGTERM SIGINT

# Keep pipe open - without this, server will get EOF
exec 3> "$PIPE"

# Start server with unbuffered output
echo "Launching Terraria server..."
unbuffer $SERVER_BIN \
    -config /config/serverconfig.txt \
    -worldpath /world \
    -logpath /world \
    < "$PIPE" &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"
echo "Command pipe: $PIPE"
echo "==================================="

# Wait for server to exit
wait $SERVER_PID
EXIT_CODE=$?

# Cleanup
exec 3>&-
rm -f "$PIPE"

echo "Server exited with code: $EXIT_CODE"
exit $EXIT_CODE
WRAPPER_EOF

# Create command helper for easy server commands
RUN cat > /usr/local/bin/tsay <<'CMD_EOF'
#!/bin/bash
# Terraria Server Command Helper
PIPE="/tmp/terraria-cmd"

if [ ! -p "$PIPE" ]; then
    echo "ERROR: Server is not running (pipe not found)"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: tsay <command>"
    echo ""
    echo "Examples:"
    echo "  tsay help          - Show all server commands"
    echo "  tsay playing       - List online players"
    echo "  tsay say Hello!    - Broadcast message"
    echo "  tsay save          - Save world"
    echo "  tsay exit          - Stop server"
    exit 1
fi

# Send command
echo "$@" > "$PIPE"
echo "✓ Command sent: $@"
CMD_EOF

# Set all permissions
RUN chmod +x /app/terraria/wrapper.sh /usr/local/bin/tsay

# Create s6 service
RUN mkdir -p /etc/services.d/terraria && \
    echo '#!/usr/bin/with-contenv bash' > /etc/services.d/terraria/run && \
    echo 'exec s6-setuidgid abc /app/terraria/wrapper.sh' >> /etc/services.d/terraria/run && \
    chmod +x /etc/services.d/terraria/run

COPY root/ /
RUN chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world", "/config"]