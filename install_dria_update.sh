#!/bin/bash

# This script installs and configures the DRIA points updater.
# It creates a worker script at /root/update_points.sh and a systemd timer.

set -euo pipefail

# === CONFIGURATION ===
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

# Default REMOTE_USER to 'driauser'
REMOTE_USER="${REMOTE_USER:-driauser}"
echo -e "👤 Using REMOTE_USER: ${GREEN}$REMOTE_USER${RESET}"

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

# SSH key setup
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  echo -e "ℹ️ Running on main server (bot).\n   Add worker keys to /home/$REMOTE_USER/.ssh/authorized_keys"
else
  echo -e "🔑 Generating or showing worker node SSH key..."
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    ssh-keygen -t rsa -b 4096 -C "$HOST_TAG" -f "$SSH_KEY_PATH" -N ""
  fi
  echo -e "Public key (copy to bot's ~/.ssh/authorized_keys):"
  cat "$SSH_KEY_PATH.pub"
fi

# === Generate non-interactive update_points.sh worker script ===
echo -e "📝 Writing worker script to ${GREEN}$SCRIPT_PATH${RESET}"
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail

# Load settings
ENV_FILE="/root/.dria_env"
source "$ENV_FILE"

# Variables
HOST_TAG="${HOST_TAG:-$(hostname)}"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="${REMOTE_USER:-driauser}"
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"
TMPFILE="/tmp/${HOST_TAG}.json"
TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Gather profiles
profiles=( )
for f in "$CONFIG_DIR"/.env.dria*; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f")"
  profiles+=( "${bn#.env.}" )
done
len=${#profiles[@]}

# Build JSON
{
  echo '{'
  echo "  \"hostname\": \"$HOST_TAG\","  
  echo "  \"timestamp\": \"$TIMESTAMP\","  
  echo "  \"points\": {"
} > "$TMPFILE"

for i in "${!profiles[@]}"; do
  p="${profiles[$i]}"
  pts=$(/root/.dria/bin/dkn-compute-launcher -p "$p" points 2>&1 | grep -oP '\\d+(?= \\\$DRIA)' || echo -1)
  sep="," 
  (( i == len-1 )) && sep=""
  printf "    \"%s\": %s%s\n" "$p" "$pts" "$sep" >> "$TMPFILE"
done

{
  echo "  }"
  echo "}"  
} >> "$TMPFILE"

# Send JSON to bot server
if [[ "$REMOTE_HOST" == "127.0.0.1" || "$REMOTE_HOST" == "localhost" ]]; then
  cp "$TMPFILE" "$REMOTE_DIR/$HOST_TAG.json"
else
  scp -o StrictHostKeyChecking=no -q "$TMPFILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/$HOST_TAG.json"
fi
EOF

chmod +x "$SCRIPT_PATH"

# === Create systemd service & timer ===
echo -e "🛠 Setting up systemd service & timer"
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

echo -e "${GREEN}✅ Installation complete!${RESET}"