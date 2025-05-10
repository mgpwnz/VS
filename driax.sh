#!/bin/bash

# Usage: $0 [--regenerate-all|-r]
#   without flags: only create missing configs/services
#   with --regenerate-all: delete and recreate all

CONFIG_DIR="/root/.dria/dkn-compute-launcher"
LOG_DIR="/var/log/dria"
MODELS_LIST="gemini-2.0-flash"
START_PORT=4001

API_KEYS_FILE="$CONFIG_DIR/api_keys.env"
PRIVATE_KEYS_FILE="$CONFIG_DIR/private_keys.env"

# Parse flags
REGENERATE_ALL=false
if [[ "$1" == "--regenerate-all" || "$1" == "-r" ]]; then
  REGENERATE_ALL=true
  echo "🔄 Regenerate-all mode enabled: will recreate every config and service"
fi

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# API_KEYS_FILE: create or offer editing
if [[ ! -f "$API_KEYS_FILE" ]]; then
  cat > "$API_KEYS_FILE" <<EOF
# Gemini API keys, one per line
# e.g.
# gemini-xyz123
# gemini-uvw789
EOF
  echo "✏️  API keys file created: $API_KEYS_FILE"
  nano "$API_KEYS_FILE"
else
  read -rp "✏️ $API_KEYS_FILE already exists. Edit now? [y/N]: " EDIT_API
  if [[ "$EDIT_API" =~ ^[Yy]$ ]]; then
    nano "$API_KEYS_FILE"
  fi
fi

# PRIVATE_KEYS_FILE: create or offer editing
if [[ ! -f "$PRIVATE_KEYS_FILE" ]]; then
  cat > "$PRIVATE_KEYS_FILE" <<EOF
# Private wallet keys, one per line
# e.g.
# 0xprivkey1
# 0xprivkey2
EOF
  echo "✏️  Private keys file created: $PRIVATE_KEYS_FILE"
  nano "$PRIVATE_KEYS_FILE"
else
  read -rp "✏️ $PRIVATE_KEYS_FILE already exists. Edit now? [y/N]: " EDIT_PRIV
  if [[ "$EDIT_PRIV" =~ ^[Yy]$ ]]; then
    nano "$PRIVATE_KEYS_FILE"
  fi
fi

# Load keys into arrays, ignoring comments/empty lines
mapfile -t API_KEYS < <(grep -Ev '^\s*(#|$)' "$API_KEYS_FILE")
mapfile -t PRIVATE_KEYS < <(grep -Ev '^\s*(#|$)' "$PRIVATE_KEYS_FILE")

# Validate presence of keys
if (( ${#API_KEYS[@]} == 0 || ${#PRIVATE_KEYS[@]} == 0 )); then
  echo "❗ Both $API_KEYS_FILE and $PRIVATE_KEYS_FILE must contain at least one key each." >&2
  exit 1
fi

# Function: check port availability
is_port_available() { ! lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

RELOAD_NEEDED=false
PORT=$START_PORT
TOTAL_KEYS=${#PRIVATE_KEYS[@]}
INDEX=1

while (( INDEX <= TOTAL_KEYS )); do
  SESSION="dria${INDEX}"
  ENV_PATH="$CONFIG_DIR/.env.$SESSION"
  SERVICE_PATH="/etc/systemd/system/$SESSION.service"
  LOG_PATH="$LOG_DIR/$SESSION.log"

  PRIVATEKEY="${PRIVATE_KEYS[INDEX-1]}"
  API_KEY="${API_KEYS[RANDOM % ${#API_KEYS[@]}]}"

  if $REGENERATE_ALL; then
    rm -f "$ENV_PATH" "$SERVICE_PATH"
  fi

  # Create .env if missing
  if [[ -f "$ENV_PATH" ]]; then
    echo "⚠️  Config exists: $ENV_PATH. Skipping .env creation."
  else
    # find a free port
    while ! is_port_available "$PORT"; do
      echo "Port $PORT busy, trying $((PORT+1))"
      PORT=$((PORT+1))
    done
    cat > "$ENV_PATH" <<EOF
## DRIA ##
DKN_WALLET_SECRET_KEY=$PRIVATEKEY
DKN_MODELS=$MODELS_LIST
DKN_P2P_LISTEN_ADDR=/ip4/0.0.0.0/tcp/$PORT

## Gemini API ##
GEMINI_API_KEY=$API_KEY

## Log levels ##
RUST_LOG=none
EOF
    echo "✅ Written config: $ENV_PATH"
  fi

  # Create systemd service if missing
  if [[ -f "$SERVICE_PATH" ]]; then
    echo "⚠️  Service exists: $SERVICE_PATH. Skipping unit creation."
  else
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Dria Compute Node - $SESSION
After=network.target

[Service]
EnvironmentFile=$ENV_PATH
ExecStart=/root/.dria/bin/dkn-compute-launcher --profile $SESSION start
WorkingDirectory=/root
User=root
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOF
    echo "✅ Created service: $SESSION"
    RELOAD_NEEDED=true
  fi

  PORT=$((PORT+1))
  INDEX=$((INDEX+1))
done

# Reload systemd if any services added
if $RELOAD_NEEDED; then
  echo "🔄 Reloading systemd"
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl list-units --type=service | grep dria

  read -rp "Start all new services now? [y/N]: " START
  if [[ "$START" =~ ^[Yy]$ ]]; then
    systemctl list-unit-files | grep dria | awk '{print $1}' | xargs -r systemctl enable --now
  fi
fi

echo "✅ Done."
echo "🔄 Reloading systemd"
