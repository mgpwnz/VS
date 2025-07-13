#!/usr/bin/env bash
set -euo pipefail

# Установка мониторинга Cysic — всё «в одном»

# Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Запустите как root или через sudo" >&2
  exit 1
fi

echo "🚀 Начинаем установку мониторинга Cysic..."

# 1) Пишем скрипт проверки
cat > /usr/local/bin/check_cysic.sh << 'EOF'
#!/usr/bin/env bash
# Мониторинг cysic.service: рестарт если «зависает» или появляются критичные ошибки.

LOGFILE=/var/log/cysic-monitor.log
MAX_AGE=$((30*60))               # 30 минут в секундах
SINCE="30 minutes ago"
PATTERNS="websocket: close 1006|server return error|Please register"

# a) Получаем самую последнюю запись
last_line=$(journalctl -u cysic.service -n1 --no-pager --output=short-iso 2>/dev/null)

# Если её нет — считаем, что сервис «завис» и рестартим
if [ -z "$last_line" ]; then
  echo "[$(date '+%F %T')] Нет записей cysic.service — рестарт" >> "$LOGFILE"
  systemctl restart cysic.service
  echo "[$(date '+%F %T')] cysic.service перезапущен (no logs)" >> "$LOGFILE"
  exit 0
fi

# b) Проверяем возраст последней записи
ts=$(echo "$last_line" | awk '{print $1" "$2}')
last_ts=$(date -d "$ts" +%s 2>/dev/null || echo 0)
age=$(( $(date +%s) - last_ts ))

if [ "$age" -gt "$MAX_AGE" ]; then
  echo "[$(date '+%F %T')] Последняя запись $age сек назад (>30м) — рестарт" >> "$LOGFILE"
  systemctl restart cysic.service
  echo "[$(date '+%F %T')] cysic.service перезапущен (stale)" >> "$LOGFILE"
  exit 0
fi

# c) Ищем критичные паттерны за последние 30 минут
journalctl -u cysic.service --since "$SINCE" --no-pager 2>/dev/null \
  | grep -E -q "$PATTERNS" && {
    echo "[$(date '+%F %T')] Найден паттерн ошибки — рестарт" >> "$LOGFILE"
    systemctl restart cysic.service
    echo "[$(date '+%F %T')] cysic.service перезапущен (error)" >> "$LOGFILE"
}

exit 0
EOF

# Убираем возможные CRLF и даём право на запуск
sed -i 's/\r$//' /usr/local/bin/check_cysic.sh 2>/dev/null || :
chmod +x /usr/local/bin/check_cysic.sh
echo "✔ /usr/local/bin/check_cysic.sh создан и помечен как исполняемый"

# 2) Создаём systemd-сервис
cat > /etc/systemd/system/check-cysic.service << 'EOF'
[Unit]
Description=Check Cysic health and restart if hung or error
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash /usr/local/bin/check_cysic.sh
EOF

echo "✔ /etc/systemd/system/check-cysic.service создан"

# 3) Создаём systemd-таймер
cat > /etc/systemd/system/check-cysic.timer << 'EOF'
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

# 4) Перезагружаем systemd и включаем таймер
systemctl daemon-reload
systemctl enable --now check-cysic.timer

echo
echo "✅ Установка завершена. Статус таймера:"
systemctl list-timers --no-pager | grep check-cysic.timer
