#!/usr/bin/env bash
set -euo pipefail

# Проверяем, что скрипт запущен с правами root
if [[ $EUID -ne 0 ]]; then
  echo "Запустите как root или через sudo" >&2
  exit 1
fi

# 1) Скрипт проверки
cat > /usr/local/bin/check_cysic.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOGFILE=/var/log/cysic-monitor.log
SINCE="30 minutes ago"
PATTERNS=(
  "websocket: close 1006"
  "server return error"
  "Please register"
)

logs=$(journalctl -u cysic.service --since "$SINCE" --no-pager)

if echo "$logs" | grep -E -q "$(IFS='|'; echo "${PATTERNS[*]}")"; then
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] Ошибка найдена — рестартим cysic.service" >> "$LOGFILE"
  systemctl restart cysic.service
  echo "[$ts] cysic.service перезапущен"       >> "$LOGFILE"
fi
EOF

chmod +x /usr/local/bin/check_cysic.sh
echo "✔ /usr/local/bin/check_cysic.sh создан и помечен как исполняемый"

# 2) systemd-сервис
cat > /etc/systemd/system/check-cysic.service <<'EOF'
[Unit]
Description=Check Cysic logs and restart on error
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check_cysic.sh
EOF

echo "✔ /etc/systemd/system/check-cysic.service создан"

# 3) systemd-таймер
cat > /etc/systemd/system/check-cysic.timer <<'EOF'
[Unit]
Description=Run check-cysic.service every 30 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "✔ /etc/systemd/system/check-cysic.timer создан"

# 4) Перезагрузка systemd и запуск таймера
systemctl daemon-reload
systemctl enable --now check-cysic.timer

echo
echo "✅ Установка завершена. Таймер запущен:"
systemctl list-timers --no-pager | grep check-cysic.timer
