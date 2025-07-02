#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  Titan Edge Monitor Installer"
echo "=========================================="

# -------------------------------
# Створюємо скрипт моніторингу
# -------------------------------
echo "[+] Creating monitoring script..."

cat >/usr/local/bin/check_titan.sh <<'EOF'
#!/usr/bin/env bash

CONTAINER_NAME="titan-edge"
PATTERNS=(
    "TITAN-EDGE CONNECTION LOST"
    "heartbeat: keepalive failed"
    "node offline or not exist"
)

LOG_OUTPUT=$(docker logs --tail 100 "$CONTAINER_NAME" 2>&1)

if [ -z "$LOG_OUTPUT" ]; then
    echo "[`date`] Немає логів. Можливо контейнер ще не запущений або ще нічого не вивів. Перезапуск не потрібен."
    exit 0
fi

RESTART_NEEDED=0

for pattern in "${PATTERNS[@]}"; do
    if echo "$LOG_OUTPUT" | grep -q "$pattern"; then
        RESTART_NEEDED=1
        break
    fi
done

if [ $RESTART_NEEDED -eq 1 ]; then
    echo "[`date`] Знайдено ознаку обриву з'єднання, перезапускаємо контейнер..."
    docker restart "$CONTAINER_NAME"
else
    echo "[`date`] З'єднання в порядку, перезапуск не потрібен."
fi
EOF

chmod +x /usr/local/bin/check_titan.sh
echo "[*] Monitoring script created at /usr/local/bin/check_titan.sh"

# -------------------------------
# Створюємо systemd сервіс
# -------------------------------
echo "[+] Creating systemd service..."

cat >/etc/systemd/system/check-titan.service <<'EOF'
[Unit]
Description=Перевірка та перезапуск titan-edge контейнера, якщо потрібно

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check_titan.sh
EOF

# -------------------------------
# Створюємо systemd таймер
# -------------------------------
echo "[+] Creating systemd timer..."

cat >/etc/systemd/system/check-titan.timer <<'EOF'
[Unit]
Description=Регулярна перевірка стану titan-edge контейнера

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min

Unit=check-titan.service

[Install]
WantedBy=timers.target
EOF

# -------------------------------
# Перезапускаємо systemd, активуємо таймер
# -------------------------------
echo "[+] Enabling and starting timer..."
systemctl daemon-reload
systemctl enable --now check-titan.timer

echo "=========================================="
echo "  Установка завершена!"
echo "  Таймер запущений: check-titan.timer"
echo "  Логи перевірок дивись командою:"
echo "  journalctl -u check-titan.service -f"
echo "=========================================="
