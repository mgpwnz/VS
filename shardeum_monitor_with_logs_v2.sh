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
    status_mapping = {
        "offline": "❌ offline",
        "waiting-for-network": "⏳ waiting-for-network",
        "standby": "🟢 standby",   # Додаємо статус standby
        "active": "🔵 active",
        "stopped": "❌ stopped",
        "unknown": "❓ unknown"  # Додайте новий статус
    }

    # Форматування hostname та IP, якщо включено
    prefix = f"{HOSTNAME} {SERVER_IP} " if INCLUDE_IP else f"{HOSTNAME} "

    # Змінні для відправки повідомлень
    message = ""

    # Перевірка на попередній статус
    if prev_status and prev_status in status_mapping:
        # Якщо статус змінився, формуємо повідомлення про зміну статусу
        current_status_display = status_mapping.get(status, "❓ unknown")  # Використовуйте статус, якщо він існує
        prev_status_display = status_mapping.get(prev_status, "❓ unknown")
        message = f"{prefix}State changed from {prev_status_display} to {current_status_display}"
    else:
        # Якщо статус новий або без зміни, формуємо повідомлення про поточний статус
        current_status_display = status_mapping.get(status, "❓ unknown")  # Використовуйте статус, якщо він існує
        message = f"{prefix}{current_status_display}"

    # Запис у лог-файл
    if not os.path.exists(LOG_PATH):
        open(LOG_PATH, 'w').close()

    with open(LOG_PATH, "a") as log_file:
        log_file.write(f"{current_time} {message}\n")

    # Відправка повідомлення
    if prev_status and prev_status in status_mapping:
        send_status_change_message(status, prev_status)
    else:
        send_default_message(status)

def send_status_change_message(current_status, previous_status):
    """Функція для відправки повідомлення про зміну статусу у Telegram."""
    if INCLUDE_IP:
        prefix = f"{HOSTNAME} {SERVER_IP} "
    else:
        prefix = f"{HOSTNAME} "

    message = f"{prefix}State changed from {STATUSES[previous_status]} to {STATUSES[current_status]}"
    
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

def send_default_message(status):
    """Функція для відправки стандартного повідомлення у Telegram."""
    if INCLUDE_IP:
        prefix = f"{HOSTNAME} {SERVER_IP} "
    else:
        prefix = f"{HOSTNAME} "

    if status == "stopped":
        message = f"{prefix}Container is not running ❌"
    elif status == "active":
        message = f"{prefix}Operator started ✅"
    elif status == "waiting-for-network":
        message = f"{prefix}State changed from ❌ offline to ⏳ waiting-for-network"
    elif status == "standby":
        message = f"{prefix}Container started 🟢"
    else:
        message = f"{prefix}Unknown state: {status}"

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
        output = result.stdout.strip()

        if result.returncode != 0:
            log_status(f"Error checking operator status: {result.stderr.strip()}")
            return "unknown"

        if "active" in output:  # Змінити на ваш реальний статус
            return "active"
        elif "stopped" in output:
            return "stopped"
        else:
            log_status(f"Unexpected output from operator status: {output}")
            return "unknown"

    except Exception as e:
        log_status(f"Exception during operator status check: {str(e)}")
        return "unknown"


def check_status_and_restart_operator():
    """Функція для перевірки статусу оператора та його запуску, якщо він зупинений."""
    output = check_operator_status()
    
    previous_status = load_last_status()

    for line in output.splitlines():
        if "state" in line:
            current_status = line.split(":", 1)[1].strip()  # Отримуємо статус
            
            # Змінюємо логіку для контролю статусу контейнера
            if current_status == "stopped":
                log_status("stopped")
                log_status("Starting the operator...", previous_status)
                restart_operator()
                return False
            elif current_status == "active":
                log_status("active", previous_status)
            elif current_status == "standby":
                log_status("standby", previous_status)  # Додаємо обробку для standby
            else:
                log_status("unknown")  # Якщо статус не вказаний, вважаємо його невідомим

    # Додати затримку перед перевіркою статусу контейнера
    time.sleep(10)  # Затримка 10 секунд

    # Перевірка статусу контейнера
    if is_container_running("shardeum-dashboard"):
        log_status("Container is running 🟢")
    else:
        log_status("Container is not running ❌")
        start_container("shardeum-dashboard")

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
            log_status(f"Failed to start GUI: {gui_result.stderr}")
    except subprocess.CalledProcessError as e:
        log_status(f"Error starting GUI: {e}")

if __name__ == "__main__":
    if not is_container_running("shardeum-dashboard"):
        log_status("Container 'shardeum-dashboard' is not running, starting the container...")
        start_container("shardeum-dashboard")

    check_status_and_restart_operator()
EOF

# Створюємо таймер systemd
TIMER_PATH="/etc/systemd/system/shardeum_monitor.timer"
cat << EOF > "$TIMER_PATH"
[Unit]
Description=Shardeum Monitor Timer

[Timer]
OnBootSec=10min
OnUnitActiveSec=${timer_interval}min
Unit=shardeum_monitor.service

[Install]
WantedBy=timers.target
EOF

# Створюємо systemd-сервіс
SERVICE_PATH="/etc/systemd/system/shardeum_monitor.service"
cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Shardeum Monitor Service

[Service]
Type=simple
ExecStart=/usr/bin/python3 "$SCRIPT_PATH"
EOF

# Перезапуск systemd для врахування нового таймера
systemctl daemon-reload
systemctl enable shardeum_monitor.timer
systemctl start shardeum_monitor.timer

echo "Скрипт успішно встановлений і запущений v1.1!"
