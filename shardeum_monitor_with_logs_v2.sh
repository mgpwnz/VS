#!/bin/bash

# === Оновлення системи та встановлення необхідних пакетів ===
apt update
apt install -y python3-pip curl
pip3 install pytz requests

# === Функція для перевірки Telegram ===
function test_telegram() {
    local message="Тестове повідомлення від Shardeum Monitor"
    local url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    response=$(curl -s -X POST "$url" -d "chat_id=$CHAT_ID&text=$message")
    
    if [[ "$response" == *'"ok":true'* ]]; then
        echo "Тестове повідомлення успішно надіслано."
        return 0
    else
        echo "Не вдалося надіслати тестове повідомлення."
        return 1
    fi
}

# === Запит на використання Telegram бота ===
read -p "Чи хочете ви використовувати Telegram бот для сповіщень (Y/N)? " use_telegram

if [[ "$use_telegram" == "Y" || "$use_telegram" == "y" ]]; then
    while true; do
        read -p "Введіть свій TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
        read -p "Введіть свій CHAT_ID: " CHAT_ID
        
        # Перевіряємо, чи вдається надіслати тестове повідомлення
        if test_telegram; then
            break
        else
            echo "Спробуйте ще раз ввести дані."
        fi
    done
else
    TELEGRAM_BOT_TOKEN=""
    CHAT_ID=""
fi

# Запит на включення IP-адреси у повідомленнях
read -p "Чи потрібно включати IP адресу в повідомленнях (Y/N)? " include_ip

# Запит на час для системного таймера (в хвилинах)
read -p "Введіть інтервал для системного таймера (хвилини, за замовчуванням 15): " timer_interval
timer_interval=${timer_interval:-15}  # Якщо нічого не введено, за замовчуванням 15 хвилин

# Шлях до Python-скрипта
SCRIPT_PATH="/root/check_shardeum_status.py"
LOG_PATH="/root/shardeum_monitor.log"  # Шлях до лог-файлу в домашній директорії

# Створюємо Python-скрипт
cat << EOF > "$SCRIPT_PATH"
import subprocess
import pytz
from datetime import datetime
import requests
import os
import socket
import time

# Конфігурація Telegram
TELEGRAM_BOT_TOKEN = "$TELEGRAM_BOT_TOKEN"
CHAT_ID = "$CHAT_ID"
LOG_PATH = "$LOG_PATH"
INCLUDE_IP = "$include_ip" == "Y"

# Отримуємо hostname і IP адреси
HOSTNAME = socket.gethostname()
SERVER_IP = subprocess.getoutput("hostname -I | awk '{print \$1}'")

# Визначаємо статуси з графічними символами
STATUSES = {
    "offline": "❌ offline",
    "waiting-for-network": "⏳ waiting-for-network",
    "standby": "🟢 standby",
    "active": "🔵 active",
    "stopped": "❌ stopped"  
}

# Змінна для зберігання попереднього статусу
LAST_STATUS_FILE = "/tmp/shardeum_last_status.txt"

def load_last_status():
    """Завантажує останній статус з файлу."""
    if os.path.exists(LAST_STATUS_FILE):
        with open(LAST_STATUS_FILE, "r") as file:
            return file.read().strip()
    return None

def save_last_status(status):
    """Зберігає останній статус у файл."""
    with open(LAST_STATUS_FILE, "w") as file:
        file.write(status)

def log_status(status, prev_status=None):
    """Функція для запису часу та статусу в лог та надсилання повідомлень у Telegram."""
    timezone = pytz.timezone('Europe/Kiev')  # Задаємо часовий пояс
    current_time = datetime.now(timezone).strftime('%Y-%m-%d %H:%M:%S')

    # Відображення статусів з графічними символами
    status_mapping = STATUSES

    # Форматування hostname та IP, якщо включено
    prefix = f"{HOSTNAME} {SERVER_IP} " if INCLUDE_IP else f"{HOSTNAME} "

    # Змінні для відправки повідомлень
    message = ""

    # Перевірка на попередній статус
    if prev_status and prev_status in status_mapping:
        current_status_display = status_mapping.get(status, "❓ unknown")
        prev_status_display = status_mapping.get(prev_status, "❓ unknown")
        message = f"{prefix}State changed from {prev_status_display} to {current_status_display}"
    else:
        current_status_display = status_mapping.get(status, "❓ unknown")
        message = f"{prefix}{current_status_display}"

    # Запис у лог-файл
    with open(LOG_PATH, "a") as log_file:
        log_file.write(f"{current_time} {message}\n")

    # Відправка повідомлення
    if prev_status and prev_status in status_mapping:
        send_status_change_message(status, prev_status)
    else:
        send_default_message(status)

def send_status_change_message(current_status, previous_status):
    """Функція для відправки повідомлення про зміну статусу у Telegram."""
    prefix = f"{HOSTNAME} {SERVER_IP} " if INCLUDE_IP else f"{HOSTNAME} "
    
    current_status_display = STATUSES.get(current_status, "❓ unknown")
    previous_status_display = STATUSES.get(previous_status, "❓ unknown")

    message = f"{prefix}State changed from {previous_status_display} to {current_status_display}"
    
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    data = {
        "chat_id": CHAT_ID,
        "text": message
    }
    try:
        response = requests.post(url, data=data)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"Error sending message: {e}")

def send_default_message(current_status):
    """Функція для відправки стандартного повідомлення у Telegram."""
    prefix = f"{HOSTNAME} {SERVER_IP} " if INCLUDE_IP else f"{HOSTNAME} "

    message = f"{prefix}{STATUSES[current_status]}"

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    data = {
        "chat_id": CHAT_ID,
        "text": message
    }
    try:
        response = requests.post(url, data=data)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"Error sending message: {e}")

def check_container_status():
    """Перевіряє статус контейнера Shardeum."""
    try:
        result = subprocess.run(["docker", "inspect", "--format", "{{.State.Status}}", "shardeum"], capture_output=True, text=True)
        return result.stdout.strip()
    except Exception as e:
        print(f"Error checking container status: {e}")
        return "unknown"

def restart_container():
    """Перезапускає контейнер Shardeum."""
    try:
        subprocess.run(["docker", "restart", "shardeum"], check=True)
        return True
    except subprocess.CalledProcessError:
        return False

# Головна логіка виконання
def main():
    last_status = load_last_status()
    
    while True:
        current_status = check_container_status()
        
        if current_status != last_status:
            log_status(current_status, last_status)
            save_last_status(current_status)

        # Затримка перед наступною перевіркою
        time.sleep(5)  # Перевіряємо статус кожні 5 секунд

if __name__ == "__main__":
    main()
EOF

# === Налаштування systemd ===
# Створюємо сервіс systemd
cat << EOF > /etc/systemd/system/shardeum_monitor.service
[Unit]
Description=Shardeum Monitor
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Створюємо таймер systemd
cat << EOF > /etc/systemd/system/shardeum_monitor.timer
[Unit]
Description=Runs Shardeum Monitor every $timer_interval minutes

[Timer]
OnActiveSec=0
OnUnitActiveSec=${timer_interval}min
Unit=shardeum_monitor.service

[Install]
WantedBy=timers.target
EOF

# === Активуємо та запускаємо таймер ===
systemctl daemon-reload
systemctl enable shardeum_monitor.timer
systemctl start shardeum_monitor.timer

echo "Скрипт завершив виконання. Таймер системи Shardeum Monitor активовано."
