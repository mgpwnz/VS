#!/usr/bin/env bash
set -euo pipefail

# Проверяем root
if [[ $EUID -ne 0 ]]; then
  echo "Запустите как root или через sudo" >&2
  exit 1
fi

# 1) Пишем скрипт проверки /usr/local/bin/check_cysic.sh
cat > /usr/local/bin/check_cysic.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOGFILE=/var/log/cysic-monitor.log
# порог «зависания» в секундах (30 минут)
MAX_AGE=$((30*60))

# Ошибки, при которых надо рестарт
PATTERNS=(
  "websocket: close 1006"
  "server return error"
  "Please register"
)

# Текущее время
now=$(date +%s)

# Последняя строка лога в ISO-формате
last_line=\$(journalctl -u cysic.service -n1 --no-pager --output=short-iso)
# Берём первый и второй столбцы: "YYYY-MM-DD HH:MM:SS"
ts=\$(echo "\$last_line" | awk '{print \$1" "\$2}')
# Переводим в epoch
last_ts=\$(date -d "\$ts" +%s || echo 0)
age=\$((now - last_ts))

if (( age > MAX_AGE )); then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Лог завис более чем на \$((MAX_AGE/60)) мин (посл. запись \$age сек назад)—рестарт" >> \$LOGFILE
  systemctl restart cysic.service
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] cysic.service перезапущен (stale)"     >> \$LOGFILE
  exit 0
fi

# Если логи свежие, ищем критичные ошибки за последние 30 минут
if journalctl -u cysic.service --since "30 minutes ago" --no-pager \
     | grep -E -q "$(IFS='|'; echo "\${PATTERNS[*]}")"; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ошибка найдена в логах—рестарт" >> \$LOGFILE
  systemctl restart cysic.service
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] cysic.service перезапущен (error)" >> \$LOGFILE
fi
EOF

chmod +x /usr/local/bin/check_cysic.sh
echo "✔ /usr/local/bin/check_cysic.sh создан"

# 2) Пишем systemd-сервис
cat > /etc/systemd/system/check-cysic.service <<'EOF'
[Unit]
Description=Check Cysic service health and restart if hung or error
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check_cysic.sh
EOF

echo "✔ /etc/systemd/system/check-cysic.service создан"

# 3) Пишем systemd-таймер
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

# 4) Перезагружаем конфиг systemd и запускаем таймер
systemctl daemon-reload
systemctl enable --now check-cysic.timer

echo
echo "✅ Установка завершена. Таймер запущен:"
systemctl list-timers --no-pager | grep check-cysic.timer
