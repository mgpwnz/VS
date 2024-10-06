#!/bin/bash

# === Оновлення системи та встановлення необхідних пакетів ===
apt update
apt install -y python3-pip
pip3 install pytz requests

# === Запит на використання Telegram бота ===
read -p "Чи хочете ви використовувати Telegram бот для сповіщень (Y/N)? " use_telegram

if [[ "$use_telegram" == "Y" || "$use_telegram" == "y" ]]; then
    while true; do
        read -p "Введіть свій TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
        read -p "Введіть свій CHAT_ID: " CHAT_ID

        # Перевірка відправки тестового повідомлення
        test_message="Тестове повідомлення для перевірки."
        url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"

        response=$(curl -s -X POST $url -d chat_id=$CHAT_ID -d text="$test_message")

        if [[ $response == *'"ok":true'* ]]; then
            echo "Повідомлення успішно надіслано в Telegram."
            break
        else
            echo "Не вдалося надіслати повідомлення. Будь ласка, перевірте TOKEN та CHAT_ID."
            echo "Введіть дані знову."
        fi
    done
else
    TELEGRAM_BOT_TOKEN=""
    CHAT_ID=""
fi

# Шлях до Python-скрипта
SCRIPT_PATH="$HOME/check_shardeum_status.py"
LOG_PATH="$HOME/shardeum_monitor.log"  # Шлях до лог-файлу в домашній директорії

# Створюємо Python-скрипт
cat << EOF > $SCRIPT_PATH
import subprocess
import pytz
from datetime import datetime
import requests
import os
import socket

TELEGRAM_BOT_TOKEN = "$TELEGRAM_BOT_TOKEN"
CHAT_ID = "$CHAT_ID"
LOG_PATH = "$LOG_PATH"
SERVER_IP = socket.gethostbyname(socket.gethostname())  # Отримуємо IP-адресу сервера

previous_status = None

def log_status(status):
    """Функція для запису часу та статусу в лог."""
    timezone = pytz.timezone('Europe/Kiev')  # Задаємо часовий пояс
    current_time = datetime.now(timezone).strftime('%Y-%m-%d %H:%M:%S')

    log_message = f"{current_time} [{SERVER_IP}] Shardeum operator status: {status}\n"
    
    # Запис у файл з обмеженням на відкриті файли
    with open(LOG_PATH, "a") as log_file:
        log_file.write(log_message)
    
    # Якщо включено Telegram сповіщення, відправляємо статус
    if TELEGRAM_BOT_TOKEN and CHAT_ID:
        send_telegram_message(log_message)

def send_telegram_message(message):
    """Функція для відправки повідомлення у Telegram."""
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    data = {
        "chat_id": CHAT_ID,
        "text": message
    }
    try:
        response = requests.post(url, data=data)
        if response.status_code != 200:
            log_status(f"Failed to send message: {response.text}")
    except Exception as e:
        log_status(f"Error sending Telegram message: {e}")

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
        log_status(f"Error checking container status: {e}")
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
            log_status(f"Container {container_name} started successfully!")
        else:
            log_status(f"Failed to start container: {result.stderr}")
    except subprocess.CalledProcessError as e:
        log_status(f"Error starting container: {e}")

def check_operator_status():
    """Функція для перевірки статусу оператора."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "status"],
            capture_output=True,
            text=True
        )
        output = result.stdout
        return output
    except subprocess.CalledProcessError as e:
        log_status(f"Error executing status command: {e}")
        return ""

def check_status_and_restart_operator():
    """Функція для перевірки статусу оператора та його запуску, якщо він зупинений."""
    global previous_status  # Дозволяємо змінювати глобальну змінну
    output = check_operator_status()
    
    for line in output.splitlines():
        if "state" in line:
            current_status = line.strip().replace("state: ", "")  # Видаляємо "state: "
            
            if previous_status != current_status:  # Якщо статус змінився
                log_status(f"State changed to '{current_status}'")
                previous_status = current_status
            
            if "stopped" in current_status:
                log_status("State is 'stopped', starting the operator...")
                restart_operator()
                return False
            else:
                log_status(f"State is '{current_status}'")  # Записуємо тільки статус

    gui_status_result = subprocess.run(
        ["docker", "exec", "shardeum-dashboard", "operator-cli", "gui", "status"],
        capture_output=True,
        text=True
    )
    gui_output = gui_status_result.stdout
    if "operator gui not running!" in gui_output:
        log_status("GUI is not running, starting the GUI...")
        start_gui()

    return True

def restart_operator():
    """Функція для запуску оператора."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "start"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            log_status("Operator started successfully!")
        else:
            log_status(f"Failed to start the operator: {result.stderr}")
    except subprocess.CalledProcessError as e:
        log_status(f"Error executing start command: {e}")

def start_gui():
    """Функція для запуску GUI."""
    try:
        gui_result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "gui", "start"],
            capture_output=True,
            text=True
        )
        if gui_result.returncode == 0:
            log_status("GUI started successfully!")
        else:
            log_status(f"Failed to start the GUI: {gui_result.stderr}")
    except subprocess.CalledProcessError as e:
        log_status(f"Error executing GUI start command: {e}")

def main():
    container_name = "shardeum-dashboard"

    # Перевірка, чи контейнер запущений
    if not is_container_running(container_name):
        log_status(f"Container {container_name} is not running. Starting it...")
        start_container(container_name)
    
    # Перевірка статусу оператора після запуску контейнера
    check_status_and_restart_operator()

# Виклик основної функції
if __name__ == "__main__":
    main()
EOF

# Задаємо виконувані права для скрипта
chmod +x $SCRIPT_PATH

# === Створення системного сервісу ===

SERVICE_PATH="/etc/systemd/system/check_shardeum_status.service"

# Створюємо systemd сервіс для автозапуску скрипта
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
