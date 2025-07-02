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

STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

if [ -z "$STATUS" ]; then
    echo "[`date`] Контейнер $CONTAINER_NAME не знайдений!"
    exit 1
fi

if [ "$STATUS" = "exited" ]; then
    echo "[`date`] Контейнер $CONTAINER_NAME у статусі exited. Перезапускаємо..."
    docker restart "$CONTAINER_NAME"
else
    echo "[`date`] Контейнер $CONTAINER_NAME у статусі $STATUS. Перезапуск не потрібен."
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
Description=Перевірка чи контейнер titan-edge працює, автоматичний перезапуск якщо потрібно

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
Description=Регулярна перевірка контейнера titan-edge

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
