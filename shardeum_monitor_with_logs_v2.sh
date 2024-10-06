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

    if prev_status and prev_status in STATUSES:
        log_message = f"{current_time} [{HOSTNAME}][{SERVER_IP}] State changed from '{STATUSES[prev_status]}' to '{STATUSES[status]}'"
    else:
        log_message = f"{current_time} [{HOSTNAME}][{SERVER_IP}] Shardeum operator status: {status}"
    
    # Запис у лог-файл
    if not os.path.exists(LOG_PATH):
        open(LOG_PATH, 'w').close()

    with open(LOG_PATH, "a") as log_file:
        log_file.write(log_message + "\n")

    if prev_status and prev_status in STATUSES:
        # Якщо статус змінився, відправляємо відповідне повідомлення
        if TELEGRAM_BOT_TOKEN and CHAT_ID:
            send_telegram_message(status, prev_status)
    else:
        # Відправка повідомлення без зміни статусу
        if TELEGRAM_BOT_TOKEN and CHAT_ID:
            send_telegram_message(status)


def send_telegram_message(status, prev_status=None):
    """Функція для відправки повідомлення у Telegram."""
    if INCLUDE_IP:
        prefix = f"{HOSTNAME} {SERVER_IP} "
    else:
        prefix = f"{HOSTNAME} "

    if prev_status:
        message = f"{prefix}State changed from {STATUSES[prev_status]} to {STATUSES[status]}"
    elif status == "stopped":
        message = f"{prefix}Container is not running ❌"
    elif status == "standby":
        message = f"{prefix}Container started 🟢"
    elif status == "active":
        message = f"{prefix}Operator started ✅"
    else:
        message = f"{prefix}{STATUSES.get(status, status)}"

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
    output = check_operator_status()
    
    previous_status = load_last_status()

    for line in output.splitlines():
        if "state" in line:
            current_status = line.split(":", 1)[1].strip()  # Отримуємо статус
            if current_status in STATUSES:
                current_status_display = STATUSES[current_status]  # Отримуємо статус з графічним символом
            else:
                current_status_display = current_status  # Якщо статус не вказаний, залишаємо як є

            if current_status != previous_status:  # Якщо статус змінився, логування та повідомлення
                log_status(f"State changed to '{current_status_display}'", previous_status)
                save_last_status(current_status)

            if current_status == "stopped":
                log_status("State is 'stopped', starting the operator...")
                restart_operator()
                return False

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
cat << EOF > $TIMER_PATH
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
cat << EOF > $SERVICE_PATH
[Unit]
Description=Shardeum Monitor Service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SCRIPT_PATH
EOF

# Перезапуск systemd для врахування нового таймера
systemctl daemon-reload
systemctl enable shardeum_monitor.timer
systemctl start shardeum_monitor.timer

echo "Скрипт успішно встановлений і запущений v6!"
