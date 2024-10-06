#!/bin/bash

# === Оновлення системи та встановлення необхідних пакетів ===
apt update
apt install -y python3-pip
pip3 install pytz requests

# === Запит на використання Telegram бота ===
read -p "Чи хочете ви використовувати Telegram бот для сповіщень (Y/N)? " use_telegram

if [[ "$use_telegram" == "Y" || "$use_telegram" == "y" ]]; then
    read -p "Введіть свій TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
    read -p "Введіть свій CHAT_ID: " CHAT_ID
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
INCLUDE_IP = "$include_ip" == "Y"

# Отримуємо hostname і IP адреси
HOSTNAME = socket.gethostname()
SERVER_IP = subprocess.getoutput("hostname -I | awk '{print \$1}'")

# Визначаємо статуси з графічними символами
STATUSES = {
    "offline": "❌ offline",
    "waiting-for-network": "⏳ waiting-for-network",
    "standby": "🟢 standby",
    "active": "🔵 active"
}

def log_status(status):
    """Функція для запису часу та статусу в лог."""
    timezone = pytz.timezone('Europe/Kiev')  # Задаємо часовий пояс
    current_time = datetime.now(timezone).strftime('%Y-%m-%d %H:%M:%S')

    log_message = f"{current_time} [{HOSTNAME}][{SERVER_IP}] Shardeum operator status: {status}\n"
    
    # Перевіряємо, чи існує лог-файл, і якщо ні, створюємо його
    if not os.path.exists(LOG_PATH):
        open(LOG_PATH, 'w').close()  # Створюємо порожній файл, якщо не існує

    try:
        # Запис у файл з обмеженням на відкриті файли
        with open(LOG_PATH, "a") as log_file:
            log_file.write(log_message)
    except Exception as e:
        print(f"Error writing to log file: {e}")  # Виводимо помилку в консоль
    
    # Якщо включено Telegram сповіщення, відправляємо статус
    if TELEGRAM_BOT_TOKEN and CHAT_ID:
        send_telegram_message(status)

def send_telegram_message(status):
    """Функція для відправки повідомлення у Telegram."""
    if INCLUDE_IP:
        message = f"{HOSTNAME} {SERVER_IP} {status}"
    else:
        message = f"{HOSTNAME} {status}"

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
    
    # Відстежуємо попередній статус, щоб уникнути спаму
    previous_status = None

    for line in output.splitlines():
        if "state" in line:
            current_status = line.split(":", 1)[1].strip()  # Отримуємо статус
            if current_status in STATUSES:
                current_status_display = STATUSES[current_status]  # Отримуємо статус з графічним символом
            else:
                current_status_display = current_status  # Якщо статус не вказаний, залишаємо як є

            if current_status != previous_status:  # Якщо статус змінився, логування та повідомлення
                previous_status = current_status
                log_status(f"State changed to '{current_status_display}'")
            else:
                log_status(f"State is '{current_status_display}'")  # Логування поточного статусу

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
Type=simple
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# === Створення таймера ===
TIMER_PATH="/etc/systemd/system/check_shardeum_status.timer"

cat << EOF > $TIMER_PATH
[Unit]
Description=Timer for Check Shardeum Status

[Timer]
OnBootSec=5min
OnUnitActiveSec=${timer_interval}min
Unit=check_shardeum_status.service

[Install]
WantedBy=timers.target
EOF

# === Запуск та активація сервісу та таймера ===
systemctl daemon-reload
systemctl enable check_shardeum_status.service
systemctl enable check_shardeum_status.timer
systemctl start check_shardeum_status.timer

# Виводимо статус сервісу та таймера
echo "Статус сервісу:"
sudo systemctl status check_shardeum_status.service
SERVICE_STATUS=$?

echo "Статус таймера:"
sudo systemctl status check_shardeum_status.timer
TIMER_STATUS=$?

if [ $SERVICE_STATUS -ne 0 ] || [ $TIMER_STATUS -ne 0 ]; then
    echo "Сервіс або таймер неактивні. Будь ласка, перевстановіть скрипт."
else
    echo "Скрипт та сервіс успішно встановлені."
fi
