#!/bin/bash

# Налаштування
SCRIPT_PATH="/root/gaianet_monitor.sh"
SERVICE_PATH="/etc/systemd/system/gaianet-monitor.service"
LOG_PATH="/var/log/gaianet_monitor.log"
ENV_PATH="/root/.wasmedge/env"

# Перевірка наявності лог-файлу
if [ ! -f "$LOG_PATH" ]; then
    touch $LOG_PATH
    chmod 644 $LOG_PATH
fi

# Створення скрипта для моніторингу
echo "Створюємо скрипт для моніторингу..."
cat << EOF > $SCRIPT_PATH
#!/bin/bash

# Завантаження змінних середовища
if [ -f "$ENV_PATH" ]; then
    source $ENV_PATH
else
    echo "\$(date): Не вдалося знайти файл зі змінними середовища $ENV_PATH" >> /var/log/gaianet_monitor.log
    exit 1
fi

# Налаштування PATH
export PATH="/root/gaianet/bin:\$PATH"

# URL для перевірки
URL="http://localhost:8080/v1/info"

# Лог-файл
LOG_PATH="/var/log/gaianet_monitor.log"

# Функція для зупинки та запуску GaiaNet
restart_gaianet() {
    echo "\$(date): Restarting GaiaNet..." >> \$LOG_PATH
    gaianet stop
    sleep 5
    gaianet start 2>&1 | tee -a \$LOG_PATH | grep -q "Port 8080 is in use"
    if [ \$? -eq 0 ]; then
        echo "\$(date): Port 8080 is in use after start. Stopping GaiaNet and retrying..." >> \$LOG_PATH
        gaianet stop
        sleep 5
        gaianet start >> \$LOG_PATH
    fi
}

# Виконуємо curl-запит
STATUS=\$(curl -s -o /dev/null -w "%{http_code}" -X POST \$URL)

# Перевірка статусу ноди
if [ "\$STATUS" -eq 000 ]; then
    echo "\$(date): Connection refused. Node is not responding." >> \$LOG_PATH
    restart_gaianet
else
    echo "\$(date): Node is running. HTTP status: \$STATUS" >> \$LOG_PATH
fi

# Перевірка, чи запущена нода
ps aux | grep -q "[w]asmedge"
if [ \$? -ne 0 ]; then
    echo "\$(date): Node process not running. Restarting GaiaNet..." >> \$LOG_PATH
    restart_gaianet
else
    echo "\$(date): Node process is running." >> \$LOG_PATH
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
if systemctl is-active --quiet gaianet-monitor.service; then
    echo "Сервіс запущено успішно."
else
    echo "Сервіс не вдалося запустити. Перевірте логи systemd."
fi

echo "Логи доступні за шляхом: $LOG_PATH"
