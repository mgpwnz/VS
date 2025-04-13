#!/bin/bash

echo "📦 Встановлення таймера DRIA Points оновлення..."

read -p "🔤 Введи HOST_TAG (ім’я цього сервера): " HOST_TAG
read -p "🌐 Введи REMOTE_HOST (IP або '127.0.0.1' для локального сервера): " REMOTE_HOST
read -p "👤 Введи REMOTE_USER (наприклад, 'driauser'): " REMOTE_USER

REMOTE_DIR="/home/$REMOTE_USER/dria_stats"
LOG_DIR="/var/log/dria"
SCRIPT_PATH="/root/update_points.sh"

echo ""
if [[ "$REMOTE_HOST" != "127.0.0.1" && "$REMOTE_HOST" != "localhost" ]]; then
  echo "🔑 Копіюємо SSH ключ на $REMOTE_USER@$REMOTE_HOST..."
  ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa <<< y >/dev/null 2>&1
  ssh-copy-id "$REMOTE_USER@$REMOTE_HOST"
else
  echo "ℹ️ REMOTE_HOST вказано як локальний — SSH не використовується."
fi

echo ""
echo "📝 Створюємо $SCRIPT_PATH..."

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
echo "  \\"hostname\\": \\"\$HOST_TAG\\"," >> "\$TEMP_FILE"
echo "  \\"timestamp\\": \\"\$TIMESTAMP\\"," >> "\$TEMP_FILE"
echo "  \\"points\\": {" >> "\$TEMP_FILE"

first=true
for file in "\$LOG_DIR"/dria*.log; do
  node=\$(basename "\$file" .log)
  value=\$(tac "\$file" | grep -m1 '\\\$DRIA Points:' | grep -oP '\\\\d+(?= total)' || echo -1)

  if [ "\$first" = true ]; then
    first=false
  else
    echo "," >> "\$TEMP_FILE"
  fi

  echo -n "    \\"\$node\\": \$value" >> "\$TEMP_FILE"
done

echo "" >> "\$TEMP_FILE"
echo "  }" >> "\$TEMP_FILE"
echo "}" >> "\$TEMP_FILE"

if [[ "\$REMOTE_HOST" == "127.0.0.1" || "\$REMOTE_HOST" == "localhost" ]]; then
  echo "📁 Копіюємо локально → \$REMOTE_DIR/\$HOST_TAG.json"
  cp "\$TEMP_FILE" "\$REMOTE_DIR/\$HOST_TAG.json"
else
  echo "📤 Надсилаємо через SCP → \$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR"
  scp -q "\$TEMP_FILE" "\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\$HOST_TAG.json"
fi
EOF

chmod +x "$SCRIPT_PATH"

echo "🛠 Створюємо systemd unit і таймер..."

cat > /etc/systemd/system/dria-update.service <<EOF
[Unit]
Description=Push DRIA Points to central bot

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
EOF

cat > /etc/systemd/system/dria-update.timer <<EOF
[Unit]
Description=Run dria-update every 3 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=dria-update.service

[Install]
WantedBy=timers.target
EOF

echo "🔄 Перезапускаємо systemd та активуємо таймер..."
systemctl daemon-reload
systemctl enable --now dria-update.timer

echo "✅ Готово! DRIA Points будуть оновлюватись автоматично кожні 3 хвилини."
