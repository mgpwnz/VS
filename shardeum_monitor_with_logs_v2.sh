#!/bin/bash

# === Налаштування системного сервісу та таймера для моніторингу Shardeum Dashboard з логами та Telegram-ботом ===

# Шлях до Python-скрипта
SCRIPT_PATH="/root/check_shardeum_status.py"
LOG_PATH="/root/shardeum_monitor.log"  # Шлях до лог-файлу
LAST_STATUS_FILE="/tmp/shardeum_last_status.txt"  # Файл для збереження попереднього статусу

# Запитуємо користувача про використання Telegram
read -p "Чи хочете ви використовувати Telegram бот для сповіщень (Y/N)? " USE_TELEGRAM

if [[ "$USE_TELEGRAM" == "Y" || "$USE_TELEGRAM" == "y" ]]; then
    read -p "Введіть свій TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
    read -p "Введіть свій CHAT_ID: " CHAT_ID
    read -p "Чи включати IP адресу сервера в повідомлення (Y/N)? " INCLUDE_IP
else
    TELEGRAM_BOT_TOKEN=""
    CHAT_ID=""
    INCLUDE_IP="N"
fi

# Встановлення необхідних компонентів
apt update
apt install python3-pip -y

# Створюємо Python-скрипт для перевірки контейнера та надсилання сповіщень
cat << EOF > $SCRIPT_PATH
import subprocess
import os
import requests
import socket

TELEGRAM_BOT_TOKEN = "$TELEGRAM_BOT_TOKEN"
CHAT_ID = "$CHAT_ID"
LAST_STATUS_FILE = "$LAST_STATUS_FILE"
INCLUDE_IP = "$INCLUDE_IP"

def send_telegram_message(message):
    """Функція для надсилання повідомлення через Telegram."""
    if TELEGRAM_BOT_TOKEN and CHAT_ID:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        payload = {"chat_id": CHAT_ID, "text": message}
        try:
            response = requests.post(url, json=payload)
            if response.status_code == 200:
                print("Повідомлення надіслано успішно.")
            else:
                print(f"Помилка при надсиланні повідомлення: {response.text}")
        except Exception as e:
            print(f"Помилка: {e}")

def get_server_ip():
    """Отримання IP адреси сервера."""
    return socket.gethostbyname(socket.gethostname())

def is_container_running(container_name):
    """Перевіряємо, чи запущений контейнер."""
    try:
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == "true"
    except subprocess.CalledProcessError as e:
        print(f"Помилка при перевірці контейнера: {e}")
        return False

def start_container(container_name):
    """Запускаємо контейнер."""
    try:
        result = subprocess.run(
            ["docker", "start", container_name],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print(f"Контейнер {container_name} успішно запущено!")
        else:
            print(f"Не вдалося запустити контейнер: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"Помилка при запуску контейнера: {e}")

def check_status_and_restart_operator():
    """Перевіряємо статус оператора та запускаємо його, якщо потрібно."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "status"],
            capture_output=True,
            text=True
        )
        
        output = result.stdout
        current_status = None
        
        for line in output.splitlines():
            if "state" in line:
                current_status = line.split(":")[-1].strip()
                break

        if current_status:
            # Зчитуємо попередній статус
            last_status = ""
            if os.path.exists(LAST_STATUS_FILE):
                with open(LAST_STATUS_FILE, "r") as f:
                    last_status = f.read().strip()

            # Якщо статус змінився, надсилаємо повідомлення
            if current_status != last_status:
                hostname = socket.gethostname()
                message = f"{hostname} "
                
                if INCLUDE_IP == "Y":
                    message += f"{get_server_ip()} "

                message += f"статус: {current_status}"
                send_telegram_message(message)

                # Зберігаємо новий статус
                with open(LAST_STATUS_FILE, "w") as f:
                    f.write(current_status)
        
        # Перевіряємо, чи потрібно перезапускати оператора
        if current_status == "stopped":
            print("Статус 'stopped', запускаємо оператора...")
            restart_operator()
        
        return True
    except subprocess.CalledProcessError as e:
        print(f"Помилка при перевірці статусу: {e}")
        return False

def restart_operator():
    """Запускаємо оператора."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "start"],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print("Оператор успішно запущено!")
        else:
            print(f"Не вдалося запустити оператора: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"Помилка при запуску оператора: {e}")

def main():
    container_name = "shardeum-dashboard"

    if not is_container_running(container_name):
        print(f"Контейнер {container_name} не запущений. Запускаємо...")
        start_container(container_name)
    
    check_status_and_restart_operator()

# Виклик основної функції
main()
EOF

# Додаємо виконувані права для скрипта
chmod +x $SCRIPT_PATH

# === Створення системного сервісу ===

SERVICE_PATH="/etc/systemd/system/check_shardeum_status.service"

cat << EOF > $SERVICE_PATH
[Unit]
Description=Check Shardeum Container and Operator Status
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/python3 /root/check_shardeum_status.py
StandardOutput=append:/root/shardeum_monitor.log
StandardError=append:/root/shardeum_monitor.log
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

# Перезавантажуємо systemd та активуємо сервіс
systemctl daemon-reload
systemctl enable check_shardeum_status.service
systemctl enable check_shardeum_status.timer
systemctl start check_shardeum_status.timer

echo "Сервіс для моніторингу Shardeum з Telegram ботом успішно налаштовано. Логи зберігаються у $LOG_PATH."
