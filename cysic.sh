#!/usr/bin/env bash
set -euo pipefail

# Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Запустите установку с правами root" >&2
  exit 1
fi

echo "🚀 Установка мониторинга Cysic..."

# 1. Скрипт проверки
cat > /usr/local/bin/check_cysic.sh <<'EOF'
#!/usr/bin/env bash
# Мониторинг cysic.service: рестарт при «зависании» или критичных ошибках

LOGFILE=/var/log/cysic-monitor.log
MAX_AGE=$((30*60))             # 30 мин в секундах
SINCE="30 minutes ago"
PATTERNS="websocket: close 1006|server return error|Please register"

# 1) Последняя строка лога
last_line=\$(journalctl -u cysic.service -n1 --no-pager --output=short-iso 2>/dev/null)

if [ -z "\$last_line" ]; then
  echo "[\$(date '+%F %T')] Нет записей cysic.service — рестарт" >> "\$LOGFILE"
  systemctl restart cysic.service
  echo "[\$(date '+%F %T')] Перезапущен (no logs)"       >> "\$LOGFILE"
  exit 0
fi

# 2) Возраст последней записи
ts=\$(printf '%s' "\$last_line" | awk '{print \$1" "\$2}')
last_ts=\$(date -d "\$ts" +%s 2>/dev/null || echo 0)
age=\$(( \$(date +%s) - last_ts ))

if [ "\$age" -gt "\$MAX_AGE" ]; then
  echo "[\$(date '+%F %T')] Запись \$age сек назад (>30м) — рестарт" >> "\$LOGFILE"
  systemctl restart cysic.service
  echo "[\$(date '+%F %T')] Перезапущен (stale)"             >> "\$LOGFILE"
  exit 0
fi

# 3) Критичные паттерны в последних 30 мин
journalctl -u cysic.service --since "\$SINCE" --no-pager 2>/dev/null \
  | grep -E -q "\$PATTERNS" && {
    echo "[\$(date '+%F %T')] Найден паттерн ошибки — рестарт" >> "\$LOGFILE"
    systemctl restart cysic.service
    echo "[\$(date '+%F %T')] Перезапущен (error)"           >> "\$LOGFILE"
}

exit 0
EOF

chmod +x /usr/local/bin/check_cysic.sh
echo "✔ Скрипт /usr/local/bin/check_cysic.sh создан"

# 2. systemd-сервис
cat > /etc/systemd/system/check-cysic.service <<'EOF'
[Unit]
Description=Check Cysic service health and restart if hung or error
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash /usr/local/bin/check_cysic.sh
EOF

echo "✔ Юнит /etc/systemd/system/check-cysic.service создан"

# 3. systemd-таймер
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

echo "✔ Таймер /etc/systemd/system/check-cysic.timer создан"

# 4. Перезагрузка systemd и запуск
systemctl daemon-reload
systemctl enable --now check-cysic.timer

echo
echo "✅ Установка завершена."
systemctl list-timers --no-pager | grep check-cysic.timer
