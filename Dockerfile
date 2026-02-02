FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

ARG VERSION="1453"
LABEL maintainer="your-email@example.com"

# Install dependencies
RUN \
 echo "**** install packages ****" && \
 apt-get update && \
 apt-get install -y \
    unzip \
    curl && \
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

# Create tserver management script
RUN cat > /usr/local/bin/tserver <<'SERVER_EOF'
#!/bin/bash
# Terraria Server Management Tool

PIPE="/tmp/terraria-cmd"

case "$1" in
    console)
        if [ ! -p "$PIPE" ]; then
            echo "ERROR: Server is not running"
            exit 1
        fi
        echo "╔═══════════════════════════════════════════════╗"
        echo "║     Terraria Server - Interactive Console    ║"
        echo "╚═══════════════════════════════════════════════╝"
        echo ""
        echo "Connected. Type commands and press Enter."
        echo "Press Ctrl+C to exit console."
        echo "───────────────────────────────────────────────"
        tail -f /world/server*.log 2>/dev/null &
        TAIL_PID=$!
        trap "kill $TAIL_PID 2>/dev/null; echo ''; echo 'Disconnected.'; exit 0" SIGINT SIGTERM
        while read -p "> " CMD; do
            [ -n "$CMD" ] && echo "$CMD" > "$PIPE"
        done
        ;;
    logs)
        echo "Watching server logs (Ctrl+C to exit)..."
        echo "───────────────────────────────────────────────"
        tail -f /world/server*.log 2>/dev/null
        ;;
    *)
        if [ -z "$1" ]; then
            echo "Terraria Server Management Tool"
            echo ""
            echo "Usage:"
            echo "  tserver console       - Interactive console with live output"
            echo "  tserver logs          - Watch server logs"
            echo "  tserver <command>     - Send single command to server"
            echo ""
            echo "Examples:"
            echo "  tserver console"
            echo "  tserver help"
            echo "  tserver playing"
            echo "  tserver save"
            echo "  tserver say Hello everyone!"
            exit 0
        fi
        if [ ! -p "$PIPE" ]; then
            echo "ERROR: Server is not running"
            exit 1
        fi
        echo "$@" > "$PIPE"
        echo "✓ Command sent: $@"
        echo "  Use 'tserver logs' or 'tserver console' to see server response"
        ;;
esac
SERVER_EOF

# Create wrapper with startup instructions
RUN cat > /app/terraria/wrapper.sh <<'WRAPPER_EOF'
#!/bin/bash

PIPE="/tmp/terraria-cmd"
SERVER_BIN="/app/terraria/TerrariaServer.bin.x86_64"
SHUTDOWN_INITIATED=0

echo "==================================="
echo "Terraria Server Initializing..."
echo "==================================="

# Verify files
if [ ! -f "$SERVER_BIN" ] || [ ! -f /config/serverconfig.txt ]; then
    echo "ERROR: Missing required files"
    exit 1
fi

# Create pipe
rm -f "$PIPE"
mkfifo "$PIPE"

# Shutdown handler
shutdown_server() {
    if [ $SHUTDOWN_INITIATED -eq 1 ]; then
        return
    fi
    SHUTDOWN_INITIATED=1
    
    echo ""
    echo "==================================="
    echo "Shutting down server..."
    echo "==================================="
    
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo "Sending save and exit command..."
        echo "exit" > "$PIPE" 2>/dev/null || true
        
        local count=0
        while kill -0 $SERVER_PID 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        if kill -0 $SERVER_PID 2>/dev/null; then
            echo "Forcing shutdown..."
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi
    
    kill $TAIL_PID 2>/dev/null || true
    rm -f "$PIPE"
    echo "Server stopped"
}

trap 'shutdown_server' SIGTERM SIGINT

# Start pipe keepalive
tail -f /dev/null > "$PIPE" &
TAIL_PID=$!

# Start server
cd /app/terraria
$SERVER_BIN -config /config/serverconfig.txt -worldpath /world -logpath /world < "$PIPE" &
SERVER_PID=$!

# Wait for server to initialize
sleep 3

# Verify server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: Server failed to start"
    exit 1
fi

# Print usage instructions after server starts
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                 Terraria Server Ready                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Server is running on port 7777"
echo ""
echo "HOW TO INTERACT WITH THE SERVER:"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  Interactive Console (recommended):"
echo "    docker exec -it terraria tserver console"
echo ""
echo "  Watch Server Logs:"
echo "    docker exec -it terraria tserver logs"
echo ""
echo "  Send Single Commands:"
echo "    docker exec terraria tserver help"
echo "    docker exec terraria tserver playing"
echo "    docker exec terraria tserver save"
echo ""
echo "  View from host machine:"
echo "    docker logs -f terraria"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""

# Wait for server
wait $SERVER_PID
EXIT_CODE=$?

shutdown_server
exit $EXIT_CODE
WRAPPER_EOF

RUN chmod +x /app/terraria/wrapper.sh /usr/local/bin/tserver

# Create s6 service
RUN mkdir -p /etc/services.d/terraria && \
    echo '#!/usr/bin/with-contenv bash' > /etc/services.d/terraria/run && \
    echo 'exec s6-setuidgid abc /app/terraria/wrapper.sh' >> /etc/services.d/terraria/run && \
    chmod +x /etc/services.d/terraria/run

COPY root/ /
RUN chmod +x /etc/cont-init.d/30-config

EXPOSE 7777
VOLUME ["/world", "/config"]