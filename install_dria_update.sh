#!/bin/bash

set -e

# === CONFIG ===
SCRIPT_PATH="/root/update_points.sh"
SERVICE_FILE="/etc/systemd/system/dria-update.service"
TIMER_FILE="/etc/systemd/system/dria-update.timer"
GREEN="\033[1;32m"
RESET="\033[0m"

read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
read -p "👤 Enter REMOTE_USER (usually 'driauser'): " REMOTE_USER
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
LOG_DIR="/var/log/dria"

# === SSH Key Setup ===
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  echo "ℹ️ You are on the main server (bot)."
  while true; do
    read -p "📥 Paste public key of a worker node to authorize access (or leave empty to stop): " PUBKEY
    if [[ -z "$PUBKEY" ]]; then
      break
    fi
    mkdir -p /home/$REMOTE_USER/.ssh
    touch /home/$REMOTE_USER/.ssh/authorized_keys
    chmod 700 /home/$REMOTE_USER/.ssh
    chmod 600 /home/$REMOTE_USER/.ssh/authorized_keys
    if grep -qxF "$PUBKEY" /home/$REMOTE_USER/.ssh/authorized_keys; then
      echo "⚠️ This key already exists. Skipping."
    else
      echo "$PUBKEY" >> /home/$REMOTE_USER/.ssh/authorized_keys
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
  echo -e "${GREEN}--------------------------------------------------"
  cat "$SSH_KEY_PATH.pub" | sed "s/^/${GREEN}/"
  echo -e "--------------------------------------------------${RESET}"
fi

# === Create update_points.sh ===
echo "📝 Creating $SCRIPT_PATH..."
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
HOST_TAG="$HOST_TAG"
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_DIR="$REMOTE_DIR"
LOG_DIR="$LOG_DIR"
TEMP_FILE="/tmp/\${HOST_TAG}.json"
TIMESTAMP=\$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "{" > "\$TEMP_FILE"
echo "  \"hostname\": \"\$HOST_TAG\"," >> "\$TEMP_FILE"
echo "  \"timestamp\": \"\$TIMESTAMP\"," >> "\$TEMP_FILE"
echo "  \"points\": {" >> "\$TEMP_FILE"

first=true
for file in "\$LOG_DIR"/dria*.log; do
  node=\$(basename "\$file" .log)
  value=\$(tac "\$file" | grep -m1 '\$DRIA Points:' | grep -oP '\\d+(?= total)' || echo -1)

  if [ "\$first" = true ]; then
    first=false
  else
    echo "," >> "\$TEMP_FILE"
  fi

  echo -n "    \"\$node\": \$value" >> "\$TEMP_FILE"
done

echo "" >> "\$TEMP_FILE"
echo "  }" >> "\$TEMP_FILE"
echo "}" >> "\$TEMP_FILE"

if [[ "\$REMOTE_HOST" == "127.0.0.1" || "\$REMOTE_HOST" == "localhost" ]]; then
  cp "\$TEMP_FILE" "\$REMOTE_DIR/\$HOST_TAG.json"
else
  if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "\$REMOTE_USER@\$REMOTE_HOST" 'exit'; then
    echo "❌ SSH connection to \$REMOTE_HOST failed"
    exit 1
  fi
  scp -q "\$TEMP_FILE" "\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\$HOST_TAG.json"
fi
EOF

chmod +x "$SCRIPT_PATH"

# === Create systemd service ===
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