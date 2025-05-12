#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
SCRIPT_PATH="/root/update_points.sh"
SERVICE_FILE="/etc/systemd/system/dria-update.service"
TIMER_FILE="/etc/systemd/system/dria-update.timer"
ENV_FILE="/root/.dria_env"
GREEN="\033[1;32m"
RESET="\033[0m"

# Load saved settings if they exist
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# Prompt for HOST_TAG and REMOTE_HOST if unset; default REMOTE_USER to 'driauser'
if [[ -z "${HOST_TAG:-}" ]]; then
  read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
fi
if [[ -z "${REMOTE_HOST:-}" ]]; then
  read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
fi
if [[ -z "${REMOTE_USER:-}" ]]; then
  REMOTE_USER="driauser"
  echo "👤 Using default REMOTE_USER: $REMOTE_USER"
fi

# Save settings for future runs
cat > "$ENV_FILE" <<EOF
HOST_TAG="$HOST_TAG"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="$REMOTE_USER"
EOF

# Directories
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"

# === SSH KEY SETUP ===
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  echo "ℹ️ You are on the main server (bot)."
  while true; do
    read -p "📥 Paste public key of a worker node to authorize access (or leave empty to stop): " PUBKEY
    [[ -z "$PUBKEY" ]] && break

    mkdir -p /home/$REMOTE_USER/.ssh
    touch /home/$REMOTE_USER/.ssh/authorized_keys
    chmod 700 /home/$REMOTE_USER/.ssh
    chmod 600 /home/$REMOTE_USER/.ssh/authorized_keys

    if grep -qxF "$PUBKEY" /home/$REMOTE_USER/.ssh/authorized_keys; then
      echo "⚠️ This key already exists. Skipping."
    else
      echo "$PUBKEY" >> /home/$REMOTE_USER/.ssh/authorized_keys
      echo "" >> /home/$REMOTE_USER/.ssh/authorized_keys
      echo "✅ Key added to /home/$REMOTE_USER/.ssh/authorized_keys"
    fi
    chown -R $REMOTE_USER:$REMOTE_USER /home/$REMOTE_USER/.ssh
  done
else
  echo "🔑 This is a worker node."
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "📁 No SSH key found, generating..."
    ssh-keygen -t rsa -b 4096 -C "$HOST_TAG" -f "$SSH_KEY_PATH" -N ""
  fi
  echo "✅ SSH key ready at $SSH_KEY_PATH"
  echo -e "📋 ${GREEN}Copy the following public key and add it to the main server's authorized_keys:${RESET}"
  echo -e "${GREEN}--------------------------------------------------${RESET}"
  cat "$SSH_KEY_PATH.pub"
  echo -e "${GREEN}--------------------------------------------------${RESET}"
fi

# === CREATE update_points.sh ===
echo "📝 Creating $SCRIPT_PATH..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail

# === DEFAULT CONFIGURATION ===
ENV_FILE="/root/.dria_env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# Prompt for required variables if unset; default REMOTE_USER to 'driauser'
if [[ -z "${HOST_TAG:-}" ]]; then
  read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
fi
if [[ -z "${REMOTE_HOST:-}" ]]; then
  read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
fi
if [[ -z "${REMOTE_USER:-}" ]]; then
  REMOTE_USER="driauser"
  echo "👤 Using default REMOTE_USER: $REMOTE_USER"
fi

# Save back to .env
cat > "$ENV_FILE" <<E2
HOST_TAG="$HOST_TAG"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="$REMOTE_USER"
E2

REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"
TEMP_FILE="/tmp/${HOST_TAG}.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Start JSON
{
  echo "{"
  echo "  \"hostname\": \"$HOST_TAG\","
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"points\": {"
} > "$TEMP_FILE"

first=true

# Gather profiles from .env.dria* files
for envfile in "$CONFIG_DIR"/.env.dria*; do
  [[ -f "$envfile" ]] || continue
  filename=$(basename "$envfile")
  profile=${filename#.env.}

  if $first; then
    first=false
  else
    echo "," >> "$TEMP_FILE"
  fi

  # Fetch points count
  pts=$(dkn-compute-launcher -p "$profile" points 2>&1 \
        | grep -oP '\d+(?= \$DRIA)' \
        || echo "-1")

  echo -n "    \"$profile\": $pts" >> "$TEMP_FILE"
done

# Close JSON
{
  echo ""
  echo "  }"
  echo "}"
} >> "$TEMP_FILE"

# Send to bot server
if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  cp "$TEMP_FILE" "$REMOTE_DIR/$HOST_TAG.json"
else
  scp -o StrictHostKeyChecking=no -q "$TEMP_FILE" \
      "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$HOST_TAG.json"
fi
EOF

chmod +x "$SCRIPT_PATH"

# === CREATE systemd SERVICE & TIMER ===
echo "🛠 Creating systemd service & timer..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Push DRIA Points to central bot

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run dria-update every 3 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=dria-update.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now dria-update.timer

echo "✅ DRIA auto-update configured successfully!"
