#!/bin/bash

# Оновлюємо пакети системи та встановлюємо python3-pip
echo "Оновлюємо систему та встановлюємо необхідні пакети..."
sudo apt update
sudo apt install -y python3-pip

# === Налаштування системного сервісу та таймера для моніторингу Shardeum Dashboard з логами ===

# Шлях до Python-скрипта, який ми будемо створювати
SCRIPT_PATH="$HOME/check_shardeum_status.py"
LOG_PATH="$HOME/shardeum_monitor.log"  # Шлях до лог-файлу в домашній директорії

# Функція для діалогу щодо налаштування Telegram бота
setup_telegram_bot() {
    read -p "Чи хочете ви налаштувати Telegram бот для сповіщень? (Y/N): " -r
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        read -p "Введіть ваш TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
        read -p "Введіть ваш CHAT_ID: " CHAT_ID
        
        echo "Налаштовуємо Telegram бот з даними:"
        echo "TELEGRAM_BOT_TOKEN: $TELEGRAM_BOT_TOKEN"
        echo "CHAT_ID: $CHAT_ID"
    else
        echo "Telegram бот не буде налаштований."
        TELEGRAM_BOT_TOKEN=""
        CHAT_ID=""
    fi
}

# Викликаємо функцію налаштування бота
setup_telegram_bot

# Створюємо Python-скрипт для моніторингу контейнера та оператора
cat << EOF > $SCRIPT_PATH
import subprocess
import logging
import os
from datetime import datetime

# Логи
LOG_FILE_PATH = os.path.expanduser('$LOG_PATH')
logging.basicConfig(
    filename=LOG_FILE_PATH,
    level=logging.INFO,
    format='%(asctime)s %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

TELEGRAM_BOT_TOKEN = "$TELEGRAM_BOT_TOKEN"
CHAT_ID = "$CHAT_ID"

def send_telegram_message(message):
    if TELEGRAM_BOT_TOKEN and CHAT_ID:
        import requests
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {"chat_id": CHAT_ID, "text": message}
        try:
            response = requests.post(url, data=data)
            if response.status_code == 200:
                logging.info(f"Message sent to Telegram: {message}")
            else:
                logging.error(f"Failed to send message: {response.text}")
        except Exception as e:
            logging.error(f"Error sending message to Telegram: {e}")

def is_container_running(container_name):
    """Функція для перевірки, чи запущений контейнер."""
    try:
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == "true"
    except subprocess.CalledProcessError as e:
        logging.error(f"Error checking container status: {e}")
        return False

def start_container(container_name):
    """Функція для запуску контейнера."""
    try:
        result = subprocess.run(
            ["docker", "start", container_name],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            logging.info(f"Container {container_name} started successfully!")
        else:
            logging.error(f"Failed to start container: {result.stderr}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error starting container: {e}")

def check_status_and_restart_operator():
    """Функція для перевірки статусу оператора та його запуску, якщо він зупинений."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "status"],
            capture_output=True,
            text=True
        )
        output = result.stdout
        if "state" in output and "stopped" in output:
            logging.info("Operator is stopped. Restarting...")
            restart_operator()
            return False
        else:
            logging.info(f"Operator status: {output.strip()}")
            return True

    except subprocess.CalledProcessError as e:
        logging.error(f"Error checking operator status: {e}")
        return False

def restart_operator():
    """Функція для запуску оператора."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "start"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            logging.info("Operator started successfully!")
        else:
            logging.error(f"Failed to start operator: {result.stderr}")
    except subprocess.CalledProcessError as e:
        logging.error(f"Error starting operator: {e}")

def main():
    container_name = "shardeum-dashboard"

    if not is_container_running(container_name):
        logging.info(f"Container {container_name} is not running. Starting...")
        start_container(container_name)

    if check_status_and_restart_operator():
        message = "Shardeum operator is running and active."
    else:
        message = "Shardeum operator was stopped and has been restarted."
    
    logging.info(message)
    send_telegram_message(message)

if __name__ == "__main__":
    main()
EOF

# Задаємо виконувані права для скрипта
chmod +x $SCRIPT_PATH

# === Створення системного сервісу ===
SERVICE_PATH="/etc/systemd/system/check_shardeum_status.service"

cat << EOF > $SERVICE_PATH
[Unit]
Description=Check Shardeum Container and Operator Status
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_PATH
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === Створення системного таймера для виконання сервісу кожні 15 хвилин ===
TIMER_PATH="/etc/systemd/system/check_shardeum_status.timer"

cat << EOF > $TIMER_PATH
[Unit]
Description=Run Shardeum Status Check every 15 minutes
Wants=check_shardeum_status.service

[Timer]
OnBootSec=1min          
OnUnitActiveSec=15min   
Persistent=true          

[Install]
WantedBy=timers.target
EOF

# Перезавантажуємо systemd, щоб застосувати зміни
systemctl daemon-reload

# Активуємо та запускаємо сервіс та таймер
systemctl enable check_shardeum_status.service
systemctl enable check_shardeum_status.timer
systemctl start check_shardeum_status.timer

echo "Сервіс та таймер для моніторингу Shardeum Dashboard успішно налаштовані і запущені. Логи зберігаються у $LOG_PATH."
