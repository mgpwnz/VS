#!/bin/bash

set -euo pipefail

# === CONFIG ===
SCRIPT_PATH="/root/update_points.sh"
SERVICE_FILE="/etc/systemd/system/dria-update.service"
TIMER_FILE="/etc/systemd/system/dria-update.timer"
ENV_FILE="/root/.dria_env"
GREEN="\033[1;32m"
RESET="\033[0m"

# Load saved settings if present
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# Default REMOTE_USER to 'driauser' if not set
REMOTE_USER="${REMOTE_USER:-driauser}"
echo "👤 Using REMOTE_USER: $REMOTE_USER"

# Prompt for HOST_TAG and REMOTE_HOST if unset
if [[ -z "${HOST_TAG:-}" ]]; then
  read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
fi
if [[ -z "${REMOTE_HOST:-}" ]]; then
  read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
fi

# Save settings for future runs
cat > "$ENV_FILE" <<EOF
HOST_TAG="$HOST_TAG"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="$REMOTE_USER"
EOF

# Directories and config path\REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"

# === SSH KEY SETUP ===
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  echo "ℹ️ Running on main server (bot). Paste worker public keys:" 
  while read -r PUBKEY && [[ -n "$PUBKEY" ]]; do
    mkdir -p /home/$REMOTE_USER/.ssh
    touch /home/$REMOTE_USER/.ssh/authorized_keys
    chmod 700 /home/$REMOTE_USER/.ssh
    chmod 600 /home/$REMOTE_USER/.ssh/authorized_keys
    if ! grep -qxF "$PUBKEY" /home/$REMOTE_USER/.ssh/authorized_keys; then
      echo "$PUBKEY" >> /home/$REMOTE_USER/.ssh/authorized_keys
      echo "✅ Key added"
    else
      echo "⚠️ Key already exists"
    fi
    chown -R $REMOTE_USER:$REMOTE_USER /home/$REMOTE_USER/.ssh
  done < <(echo "")
else
  echo "🔑 Setting up worker node SSH key..."
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    ssh-keygen -t rsa -b 4096 -C "$HOST_TAG" -f "$SSH_KEY_PATH" -N ""
  fi
  echo -e "📋 ${GREEN}Public key:${RESET}"
  cat "$SSH_KEY_PATH.pub"
fi

# === CREATE update_points.sh ===
echo "📝 Writing $SCRIPT_PATH..."
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail

# Load env
ENV_FILE="/root/.dria_env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# Defaults
REMOTE_USER="${REMOTE_USER:-driauser}"
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"
TMPFILE="/tmp/${HOST_TAG}.json"
TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Gather profiles
profiles=( )
for f in "$CONFIG_DIR"/.env.dria*; do
  [[ -f "$f" ]] || continue
  profiles+=("${f##*/.env.}")
done
len=${#profiles[@]}

# Build JSON
{
  echo '{'
  echo '  "hostname": "'$HOST_TAG'",'
  echo '  "timestamp": "'$TIMESTAMP'",'
  echo '  "points": {'
} > "$TMPFILE"

for i in "${!profiles[@]}"; do
  p="${profiles[$i]}"
  pts=$(dkn-compute-launcher -p "$p" points 2>&1 | grep -oP '\\d+(?= \\\$DRIA)' || echo -1)
  sep="," 
  (( i == len-1 )) && sep=""
  echo "    \"$p\": $pts$sep" >> "$TMPFILE"
done

{
  echo '  }'
  echo '}'
} >> "$TMPFILE"

# Send JSON
if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  cp "$TMPFILE" "$REMOTE_DIR/$HOST_TAG.json"
else
  scp -o StrictHostKeyChecking=no -q "$TMPFILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$HOST_TAG.json"
fi
EOF

chmod +x "$SCRIPT_PATH"

# === CREATE service & timer ===
echo "🛠 Installing systemd unit..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Push DRIA points

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run update_points every 3m

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=dria-update.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now dria-update.timer

echo "✅ Installed successfully"
