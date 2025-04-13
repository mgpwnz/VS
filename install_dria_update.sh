#!/bin/bash

read -p "👉 Введи унікальне ім’я цього сервера (HOST_TAG): " HOST_TAG
read -p "🌐 Введи IP або домен основного сервера з ботом (REMOTE_HOST): " REMOTE_HOST

REMOTE_USER="root"
REMOTE_DIR="/root/dria_stats"
LOG_DIR="/var/log/dria"
TEMP_SCRIPT="/root/update_points.sh"

echo ""
echo "🔑 Генеруємо SSH ключ, якщо не існує..."
[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

echo ""
echo "📤 Надсилаємо SSH ключ на $REMOTE_USER@$REMOTE_HOST..."
ssh-copy-id -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST"

echo ""
echo "📝 Створюємо скрипт $TEMP_SCRIPT..."

cat > "$TEMP_SCRIPT" <<EOF
#!/bin/bash

HOST_TAG="$HOST_TAG"
REMOTE_USER="$REMOTE_USER"
REMOTE_HOST="$REMOTE_HOST"
REMOTE_DIR="$REMOTE_DIR"
LOG_DIR="$LOG_DIR"
TEMP_FILE="/tmp/\${HOST_TAG}.json"

echo "{" > "\$TEMP_FILE"
echo "  \\"hostname\\": \\"\$HOST_TAG\\"," >> "\$TEMP_FILE"
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

scp -q "\$TEMP_FILE" "\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\$HOST_TAG.json"
EOF

chmod +x "$TEMP_SCRIPT"

echo ""
echo "🛠 Створюємо systemd сервіс і таймер..."

cat > /etc/systemd/system/dria-update.service <<EOF
[Unit]
Description=Push DRIA Points to central bot

[Service]
Type=oneshot
ExecStart=$TEMP_SCRIPT
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

echo ""
echo "🚀 Активуємо таймер..."
systemctl daemon-reload
systemctl enable --now dria-update.timer

echo ""
echo "✅ Готово! Сервер $HOST_TAG тепер буде відправляти DRIA Points на $REMOTE_HOST кожні 3 хв."
