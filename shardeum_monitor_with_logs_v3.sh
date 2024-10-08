#!/bin/bash

# Перевірка, чи користувач root
if [ "$EUID" -ne 0 ]; then
    echo "Будь ласка, запустіть скрипт з правами root."
    exit
fi

# Змінні конфігурації
LOG_FILE="/root/shardeum_validator.log"
SERVICE_FILE="/etc/systemd/system/shardeum-validator.service"
SCRIPT_FILE="/usr/local/bin/shardeum_validator.sh"
BOT_SCRIPT="/usr/local/bin/shardeum_telegram_bot.sh"

# Запит конфігурації Telegram бота
read -p "Встановити Telegram Bot для сповіщень про статус? (Y/N): " install_telegram
if [[ $install_telegram =~ ^[Yy]$ ]]; then
    read -p "Введіть ваш TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
    read -p "Введіть ваш TELEGRAM_CHAT_ID: " TELEGRAM_CHAT_ID
    read -p "Додати IP сервера до сповіщень у Telegram? (Y/N): " include_ip
    if [[ $include_ip =~ ^[Yy]$ ]]; then
        INCLUDE_IP="true"
    else
        INCLUDE_IP="false"
    fi
fi

# Створюємо скрипт для управління Shardeum валідатором
cat <<EOF > $SCRIPT_FILE
#!/bin/bash

# Шлях до лог файлу
LOG_FILE="/root/shardeum_validator.log"
TIMEZONE="Europe/Kyiv"

# Function to log status with timestamp in UTC+2 (Kyiv)
log_status() {
    # Перевіряємо чи контейнер працює
    CONTAINER_STATUS=$(docker inspect -f '{{.State.Running}}' shardeum-dashboard)

    if [ "$CONTAINER_STATUS" != "true" ]; then
        echo "[$(date)] Контейнер зупинений, спроба запуску..." >> $LOG_FILE
        docker start shardeum-dashboard >> $LOG_FILE 2>&1

        # Перевіряємо чи вдалося запустити контейнер
        CONTAINER_STATUS=$(docker inspect -f '{{.State.Running}}' shardeum-dashboard)
        if [ "$CONTAINER_STATUS" != "true" ]; then
            echo "[$(date)] Помилка запуску контейнера." >> $LOG_FILE
            return
        else
            echo "[$(date)] Контейнер успішно запущено." >> $LOG_FILE
        fi
    fi

    # Retrieve the current state directly
    STATUS=$(docker exec shardeum-dashboard operator-cli status | grep -i "state:" | awk '{print $2}')

    # Get the current timestamp in the specified timezone
    TIMESTAMP=$(TZ=$TIMEZONE date '+%Y-%m-%d %H:%M UTC+2')

    # Log the statuses
    echo "[$TIMESTAMP] Node Status: $STATUS" >> $LOG_FILE

    # If the node is offline, start it
    if [ "$STATUS" == "offline" ]; then
        echo "[$TIMESTAMP] Node is offline, attempting to start..." >> $LOG_FILE
        docker exec shardeum-dashboard operator-cli start >> $LOG_FILE 2>&1
    fi
}

# Запускаємо log_status кожні 15 хвилин
while true; do
    log_status
    sleep 900  # 15 хвилин
done
EOF

# Робимо скрипт виконуваним
chmod +x $SCRIPT_FILE

# Створюємо systemd сервіс для валідатора
cat <<EOF > $SERVICE_FILE
[Unit]
Description=Shardeum Validator Manager
After=docker.service
Requires=docker.service

[Service]
ExecStart=$SCRIPT_FILE
Restart=always
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
EOF

# Перезавантажуємо systemd і активуємо сервіс
systemctl daemon-reload
systemctl enable shardeum-validator.service
systemctl start shardeum-validator.service

echo "Shardeum Validator systemd service встановлено та запущено."

# Якщо обрано встановлення Telegram бота, створюємо скрипт бота
if [[ $install_telegram =~ ^[Yy]$ ]]; then
cat <<EOF > $BOT_SCRIPT
#!/bin/bash

# Змінні Telegram бота
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
INCLUDE_IP="$INCLUDE_IP"

PREV_STATUS=""

# Функція для відправки повідомлення у Telegram
send_telegram_message() {
    local MESSAGE="\$1"
    MESSAGE=\$(echo -e "\$MESSAGE")
    curl -s -X POST https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage -d chat_id=\$TELEGRAM_CHAT_ID -d text="\$MESSAGE" >> /root/shardeum_telegram_bot.log 2>&1
}

# Функція для перевірки статусу і відправки повідомлення
check_status() {
    docker exec shardeum-dashboard /bin/bash -c "echo 'operator-cli status | grep -i \"state:\" | awk \'{print \$2}\'' > /tmp/get_status.sh"
    docker exec shardeum-dashboard chmod +x /tmp/get_status.sh

    STATUS=\$(docker exec shardeum-dashboard /bin/bash -c "/tmp/get_status.sh")

    HOSTNAME=\$(hostname)
    if [ "\$INCLUDE_IP" == "true" ]; then
        SERVER_IP=\$(hostname -I | awk '{print \$1}')
    else
        SERVER_IP=""
    fi

    if [ "\$STATUS" == "offline" ]; then
        STATUS_EMOJI="❌ offline"
    elif [ "\$STATUS" == "waiting-for-network" ]; then
        STATUS_EMOJI="⏳ waiting-for-network"
    elif [ "\$STATUS" == "standby" ]; then
        STATUS_EMOJI="🟢 standby"
    elif [ "\$STATUS" == "active" ]; then
        STATUS_EMOJI="🔵 active"
    fi

    if [ "\$STATUS" != "\$PREV_STATUS" ]; then
        MESSAGE="Host: \$HOSTNAME"
        if [ -n "\$SERVER_IP" ]; then
            MESSAGE="\$MESSAGE\nIP: \$SERVER_IP"
        fi
        MESSAGE="\$MESSAGE\nStatus: \$STATUS_EMOJI"
        send_telegram_message "\$MESSAGE"
        
        PREV_STATUS="\$STATUS"
    fi
}

# Запускаємо check_status кожні 5 хвилин
while true; do
    check_status
    sleep 300  # 5 хвилин
done
EOF

# Робимо скрипт бота виконуваним
chmod +x $BOT_SCRIPT

# Створюємо systemd сервіс для Telegram бота
cat <<EOF > /etc/systemd/system/shardeum-telegram-bot.service
[Unit]
Description=Shardeum Telegram Bot
After=docker.service
Requires=docker.service

[Service]
ExecStart=$BOT_SCRIPT
Restart=always
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
EOF

# Перезавантажуємо systemd і активуємо сервіс Telegram бота
systemctl daemon-reload
systemctl enable shardeum-telegram-bot.service
systemctl start shardeum-telegram-bot.service

echo "Shardeum Telegram bot встановлено та запущено."
fi

echo "Інсталяція завершена."
