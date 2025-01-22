#!/bin/bash

# Налаштування
SCRIPT_PATH="/root/gaianet_monitor.sh"
SERVICE_PATH="/etc/systemd/system/gaianet-monitor.service"
LOG_PATH="/var/log/gaianet_monitor.log"

# Створення лог-файлу, якщо його немає
[ ! -f "$LOG_PATH" ] && touch "$LOG_PATH" && chmod 644 "$LOG_PATH"

# Створення скрипта для моніторингу
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

# Завантаження середовища з файлу
if [ -f /root/.wasmedge/env ]; then
    source /root/.wasmedge/env
else
    echo "$(date): /root/.wasmedge/env не знайдено." >> /var/log/gaianet_monitor.log
    exit 1
fi

# URL для перевірки
URL="http://localhost:8080/v1/info"
LOG_PATH="/var/log/gaianet_monitor.log"

# Функція для зупинки та запуску GaiaNet
restart_gaianet() {
    echo "$(date): Restarting GaiaNet..." >> "$LOG_PATH"
    /root/gaianet/bin/gaianet stop >> "$LOG_PATH" 2>&1 || echo "$(date): Failed to stop GaiaNet." >> "$LOG_PATH"
    sleep 5
    /root/gaianet/bin/gaianet start >> "$LOG_PATH" 2>&1
    sleep 20
}

# Перевірка статусу GaiaNet
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
if [ "$STATUS" -eq 000 ]; then
    echo "$(date): Connection refused. Node is not responding." >> "$LOG_PATH"
    restart_gaianet
else
    echo "$(date): Node is running. HTTP status: $STATUS" >> "$LOG_PATH"
fi

# Перевірка процесу WasmEdge
if ! pgrep -f "[w]asmedge" > /dev/null; then
    echo "$(date): Node process not running. Restarting GaiaNet..." >> "$LOG_PATH"
    restart_gaianet
else
    echo "$(date): Node process is running." >> "$LOG_PATH"
fi
EOF


chmod +x "$SCRIPT_PATH"

# Створення systemd-сервісу
cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Monitor Gaianet Node and Restart if Necessary
After=network.target

[Service]
Type=simple
Environment="PATH=/root/.wasmedge/bin:/root/gaianet/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=/root/.wasmedge/lib"
Environment="LIBRARY_PATH=/root/.wasmedge/lib"
Environment="C_INCLUDE_PATH=/root/.wasmedge/include"
Environment="CPLUS_INCLUDE_PATH=/root/.wasmedge/include"
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=240

[Install]
WantedBy=multi-user.target
EOF

# Активування та запуск служби
systemctl daemon-reload
systemctl enable gaianet-monitor.service
systemctl start gaianet-monitor.service

# Перевірка статусу служби
if systemctl is-active --quiet gaianet-monitor.service; then
    echo "Сервіс запущено успішно."
else
    echo "Сервіс не вдалося запустити. Перевірте логи systemd."
fi

echo "Логи доступні за шляхом: $LOG_PATH"
