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

# Create wrapper with proper error handling
RUN cat > /app/terraria/wrapper.sh <<'WRAPPER_EOF'
#!/bin/bash

PIPE="/tmp/terraria-cmd"
SERVER_BIN="/app/terraria/TerrariaServer.bin.x86_64"

echo "==================================="
echo "Terraria Server Wrapper Starting"
echo "==================================="

# Verify server binary exists and is executable
if [ ! -f "$SERVER_BIN" ]; then
    echo "ERROR: Server binary not found at $SERVER_BIN"
    exit 1
fi

if [ ! -x "$SERVER_BIN" ]; then
    echo "ERROR: Server binary is not executable"
    exit 1
fi

# Verify config exists
if [ ! -f /config/serverconfig.txt ]; then
    echo "ERROR: Configuration file not found"
    exit 1
fi

echo "✓ Server binary found"
echo "✓ Configuration found"

# Create pipe
rm -f "$PIPE"
mkfifo "$PIPE"
echo "✓ Command pipe created: $PIPE"

# Shutdown handler
shutdown_server() {
    echo "==================================="
    echo "Shutdown signal received"
    echo "==================================="
    
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo "Sending exit command..."
        echo "exit" > "$PIPE" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local count=0
        while kill -0 $SERVER_PID 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            count=$((count + 1))
            echo "Waiting for server to stop... ($count/30)"
        done
        
        # Force kill if needed
        if kill -0 $SERVER_PID 2>/dev/null; then
            echo "Force stopping server..."
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi
    
    rm -f "$PIPE"
    echo "Server stopped"
    exit 0
}

trap 'shutdown_server' SIGTERM SIGINT EXIT

# Start a background process to keep pipe open
tail -f /dev/null > "$PIPE" &
TAIL_PID=$!
echo "✓ Pipe keepalive started (PID: $TAIL_PID)"

# Start server with output
echo "==================================="
echo "Starting Terraria Server..."
echo "Command: $SERVER_BIN -config /config/serverconfig.txt -worldpath /world -logpath /world"
echo "==================================="

cd /app/terraria

$SERVER_BIN \
    -config /config/serverconfig.txt \
    -worldpath /world \
    -logpath /world < "$PIPE" &

SERVER_PID=$!
echo "Server process started (PID: $SERVER_PID)"

# Check if process is still running after 2 seconds
sleep 2
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: Server process died immediately!"
    echo "Check /world/server.log for details"
    exit 1
fi

echo "✓ Server is running"
echo "==================================="

# Wait for server
wait $SERVER_PID
EXIT_CODE=$?

# Cleanup
kill $TAIL_PID 2>/dev/null || true
rm -f "$PIPE"

echo "Server exited with code: $EXIT_CODE"
exit $EXIT_CODE
WRAPPER_EOF

# Create command helper
RUN cat > /usr/local/bin/tsay <<'CMD_EOF'
#!/bin/bash
PIPE="/tmp/terraria-cmd"

if [ ! -p "$PIPE" ]; then
    echo "ERROR: Server is not running (pipe not found)"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: tsay <command>"
    echo "Examples: tsay help | tsay playing | tsay save"
    exit 1
fi

echo "$@" > "$PIPE"
echo "Command sent: $@"
CMD_EOF

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