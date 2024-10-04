#!/bin/bash

# === Налаштування системного сервісу та таймера для моніторингу Shardeum Dashboard з логами ===

# Шлях до Python-скрипта, який ми будемо створювати
SCRIPT_PATH="/root/check_shardeum_status.py"
LOG_PATH="/root/shardeum_monitor.log"  # Шлях до лог-файлу в домашній директорії

# Створюємо Python-скрипт, який перевіряє контейнер та оператор
cat << 'EOF' > $SCRIPT_PATH
import subprocess

def is_container_running(container_name):
    """Функція для перевірки, чи запущений контейнер."""
    try:
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True
        )
        # Перевіряємо, чи контейнер запущений
        return result.stdout.strip() == "true"
    except subprocess.CalledProcessError as e:
        print(f"Error checking container status: {e}")
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
            print(f"Container {container_name} started successfully!")
        else:
            print(f"Failed to start container: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"Error starting container: {e}")

def check_status_and_restart_operator():
    """Функція для перевірки статусу оператора та його запуску, якщо він зупинений."""
    try:
        result = subprocess.run(
            ["docker", "exec", "shardeum-dashboard", "operator-cli", "status"],
            capture_output=True,
            text=True
        )
        
        output = result.stdout
        
        for line in output.splitlines():
            if "state" in line:
                if "stopped" in line:
                    print("State is 'stopped', starting the operator...")
                    restart_operator()
                    return False
                else:
                    print(f"Current state: {line}")
                    return True
    except subprocess.CalledProcessError as e:
        print(f"Error executing status command: {e}")
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
            print("Operator started successfully!")
        else:
            print(f"Failed to start the operator: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"Error executing start command: {e}")

def main():
    container_name = "shardeum-dashboard"

    # Перевірка, чи контейнер запущений
    if not is_container_running(container_name):
        print(f"Container {container_name} is not running. Starting it...")
        start_container(container_name)
    
    # Перевірка статусу оператора після запуску контейнера
    check_status_and_restart_operator()

# Виклик основної функції
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

[Timer]
OnBootSec=1min          # Запуск через 1 хвилину після старту системи
OnUnitActiveSec=15min   # Повторювати кожні 15 хвилин
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
