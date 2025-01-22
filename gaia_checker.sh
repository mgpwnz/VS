#!/bin/bash

# Налаштування
SCRIPT_PATH="/root/gaianet_monitor.sh"
SERVICE_PATH="/etc/systemd/system/gaianet-monitor.service"
LOG_PATH="/var/log/gaianet_monitor.log"

# Перевірка наявності лог-файлу
if [ ! -f "$LOG_PATH" ]; then
    touch "$LOG_PATH"
    chmod 644 "$LOG_PATH"
fi

# Створення скрипта для моніторингу
echo "Створюємо скрипт для моніторингу..."
cat << EOF > "$SCRIPT_PATH"
#!/bin/bash

# Налаштування PATH
export PATH="/root/.wasmedge/bin:/root/gaianet/bin:$PATH"
export LD_LIBRARY_PATH="/root/.wasmedge/lib"
export LIBRARY_PATH="/root/.wasmedge/lib"
export C_INCLUDE_PATH="/root/.wasmedge/include"
export CPLUS_INCLUDE_PATH="/root/.wasmedge/include"

# URL для перевірки
URL="http://localhost:8080/v1/info"

# Лог-файл
LOG_PATH="/var/log/gaianet_monitor.log"

# Функція для зупинки та запуску GaiaNet
restart_gaianet() {
    echo "\$(date): Restarting GaiaNet..." >> "\$LOG_PATH"
    /root/gaianet/bin/gaianet stop
    sleep 5
    /root/gaianet/bin/gaianet start >> "\$LOG_PATH" 2>&1
    sleep 20
}

# Перевірка доступності порту 8080
check_port() {
    if lsof -i :8080 > /dev/null; then
        echo "\$(date): Port 8080 is already in use." >> "\$LOG_PATH"
        /root/gaianet/bin/gaianet stop
        sleep 5
        /root/gaianet/bin/gaianet start >> "\$LOG_PATH" 2>&1
    fi
}

# Виконуємо curl-запит
STATUS=\$(curl -s -o /dev/null -w "%{http_code}" "\$URL")

# Перевірка статусу ноди
if [ "\$STATUS" -eq 000 ]; then
    echo "\$(date): Connection refused. Node is not responding." >> "\$LOG_PATH"
    restart_gaianet
else
    echo "\$(date): Node is running. HTTP status: \$STATUS" >> "\$LOG_PATH"
fi

# Перевірка, чи запущена нода
if ! pgrep -f "[w]asmedge" > /dev/null; then
    echo "\$(date): Node process not running. Restarting GaiaNet..." >> "\$LOG_PATH"
    restart_gaianet
else
    echo "\$(date): Node process is running." >> "\$LOG_PATH"
fi
EOF

# Надаємо права на виконання
chmod +x "$SCRIPT_PATH"

# Створення systemd-сервісу
echo "Створюємо systemd-сервіс..."
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
