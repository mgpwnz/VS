#!/bin/bash

# === Скрипт для видалення сервісу та таймера для Shardeum Status Check ===

# Шлях до Python-скрипта
SCRIPT_PATH="$HOME/check_shardeum_status.py"

# Шляхи до сервісу та таймера
SERVICE_PATH="/etc/systemd/system/check_shardeum_status.service"
TIMER_PATH="/etc/systemd/system/check_shardeum_status.timer"

# Зупиняємо та деактивуємо таймер та сервіс
echo "Зупинка сервісу та таймера..."
sudo systemctl stop check_shardeum_status.timer
sudo systemctl stop check_shardeum_status.service
sudo systemctl disable check_shardeum_status.timer
sudo systemctl disable check_shardeum_status.service

# Видаляємо файли сервісу та таймера
echo "Видалення файлів сервісу та таймера..."
sudo rm -f $SERVICE_PATH
sudo rm -f $TIMER_PATH

# Видалення Python-скрипта
echo "Видалення Python-скрипта..."
rm -f $SCRIPT_PATH

# Оновлення системи
echo "Оновлення системи..."
sudo systemctl daemon-reload

echo "Видалення завершено. Всі компоненти успішно видалені."