#!/bin/bash

# Installer for DRIA points updater: sets up worker script, systemd service, and timer
set -euo pipefail

# Configuration paths\ nSCRIPT_PATH="/root/update_points.sh"
SERVICE_FILE="/etc/systemd/system/dria-update.service"
TIMER_FILE="/etc/systemd/system/dria-update.timer"
ENV_FILE="/root/.dria_env"
GREEN="\033[1;32m"
RESET="\033[0m"

# Load saved settings
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# Defaults
REMOTE_USER="${REMOTE_USER:-driauser}"
echo -e "👤 Using REMOTE_USER: ${GREEN}$REMOTE_USER${RESET}"

# Prompt for HOST_TAG and REMOTE_HOST if unset
if [[ -z "${HOST_TAG:-}" ]]; then
  read -p "🖥️ Enter HOST_TAG (this server name): " HOST_TAG
fi
if [[ -z "${REMOTE_HOST:-}" ]]; then
  read -p "🌍 Enter REMOTE_HOST (bot server IP or 127.0.0.1): " REMOTE_HOST
fi

# Save settings
cat > "$ENV_FILE" <<EOF
HOST_TAG="$HOST_TAG"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="$REMOTE_USER"
EOF

# Worker SSH key generation (skip on bot)
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [[ "$REMOTE_HOST" != "127.0.0.1" && "$REMOTE_HOST" != "localhost" ]]; then
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    ssh-keygen -t rsa -b 4096 -C "$HOST_TAG" -f "$SSH_KEY_PATH" -N ""
  fi
  echo -e "📋 ${GREEN}Public key for worker:${RESET}"
  cat "$SSH_KEY_PATH.pub"
fi

# Create worker script
cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail

# Load environment
source "/root/.dria_env"

# Variables
HOST_TAG="${HOST_TAG:-$(hostname)}"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_USER="${REMOTE_USER:-driauser}"
REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
CONFIG_DIR="/root/.dria/dkn-compute-launcher"
TMPFILE="/tmp/${HOST_TAG}.json"
TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Collect profiles
profiles=()
for f in "$CONFIG_DIR"/.env.dria*; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f")"
  profiles+=("${bn#.env.}")
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
  comma="," 
  (( i == len-1 )) && comma=""
  printf '    "%s": %s%s
' "$p" "$pts" "$comma" >> "$TMPFILE"
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

echo -e "🛠 Setting up systemd service & timer"
# Create service file
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Push DRIA Points to central bot

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

# Create timer file
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run update_points every 3 minutes

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
