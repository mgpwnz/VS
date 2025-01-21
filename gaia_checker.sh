#!/bin/bash

# Налаштування
SCRIPT_PATH="/root/gaianet_monitor.sh"
SERVICE_PATH="/etc/systemd/system/gaianet-monitor.service"
LOG_PATH="/var/log/gaianet_monitor.log"

# Створення скрипта для моніторингу
echo "Створюємо скрипт для моніторингу..."
cat << 'EOF' > $SCRIPT_PATH
#!/bin/bash

# Налаштування PATH
export PATH="/root/gaianet/bin:$PATH"

# URL для перевірки
URL="http://localhost:8080/v1/info"

# Виконуємо curl-запит
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $URL)

# Перевірка статусу
if [ "$STATUS" -eq 000 ]; then
    echo "$(date): Connection refused. Restarting gaianet..." >> /var/log/gaianet_monitor.log
    gaianet stop
    gaianet start
else
    echo "$(date): Node is running. HTTP status: $STATUS" >> /var/log/gaianet_monitor.log
fi
EOF

# Надаємо права на виконання
chmod +x $SCRIPT_PATH

# Створення systemd-сервісу
echo "Створюємо systemd-сервіс..."
cat << EOF > $SERVICE_PATH
[Unit]
Description=Monitor Gaianet Node and Restart if Necessary
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

# Перезавантаження systemd, запуск і активація сервісу
echo "Активуємо сервіс..."
systemctl daemon-reload
systemctl enable gaianet-monitor.service
systemctl start gaianet-monitor.service

# Перевірка статусу
echo "Сервіс запущено. Перевірка статусу:"
systemctl status gaianet-monitor.service

echo "Логи доступні за шляхом: $LOG_PATH"