#!/bin/bash

set -e

# === CONFIG ===
SCRIPT_PATH="/root/update_points.sh"
SERVICE_FILE="/etc/systemd/system/dria-update.service"
TIMER_FILE="/etc/systemd/system/dria-update.timer"

read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
read -p "👤 Enter REMOTE_USER (usually 'driauser'): " REMOTE_USER
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
LOG_DIR="/var/log/dria"

# === Optional SSH Key Generation (only on 127.0.0.1 aka main server) ===
if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  echo "🔐 Checking for SSH key..."
  if [[ ! -f ~/.ssh/id_rsa ]]; then
    echo "📁 No SSH key found, generating..."
    ssh-keygen -t rsa -b 4096 -C "dria-bot" -f ~/.ssh/id_rsa -N ""
  fi
  echo "✅ SSH key found: ~/.ssh/id_rsa.pub"
  read -p "📋 Do you want to print your public key to connect other nodes? (y/n): " SHOW_KEY
  if [[ "$SHOW_KEY" == "y" ]]; then
    echo "----- COPY THIS PUBLIC KEY TO ALL OTHER NODES -----"
    cat ~/.ssh/id_rsa.pub
    echo "--------------------------------------------------"
  fi
else
  echo "🔑 This is a worker node."
  read -p "📥 Paste public key of main server here: " PUBKEY
  mkdir -p ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  grep -qxF "$PUBKEY" ~/.ssh/authorized_keys || echo "$PUBKEY" >> ~/.ssh/authorized_keys
  echo "✅ Public key added to ~/.ssh/authorized_keys"
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
