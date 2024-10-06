#!/bin/bash

# Шлях до Python-скрипта
SCRIPT_PATH="/root/check_shardeum_status.py"

# Шляхи до systemd-сервісу та таймера
SERVICE_PATH="/etc/systemd/system/shardeum_monitor.service"
TIMER_PATH="/etc/systemd/system/shardeum_monitor.timer"

# Зупиняємо і видаляємо таймер та сервіс
echo "Зупиняємо таймер і сервіс..."
systemctl stop shardeum_monitor.timer
systemctl stop shardeum_monitor.service

echo "Видаляємо таймер і сервіс..."
systemctl disable shardeum_monitor.timer
systemctl disable shardeum_monitor.service

# Видаляємо файли скрипта і лог-файлу
if [[ -f $SCRIPT_PATH ]]; then
    echo "Видаляємо скрипт: $SCRIPT_PATH"
    rm -f $SCRIPT_PATH
else
    echo "Скрипт не знайдено: $SCRIPT_PATH"
fi

if [[ -f /root/shardeum_monitor.log ]]; then
    echo "Видаляємо лог-файл: /root/shardeum_monitor.log"
    rm -f /root/shardeum_monitor.log
else
    echo "Лог-файл не знайдено: /root/shardeum_monitor.log"
fi

# Видаляємо systemd файли
if [[ -f $SERVICE_PATH ]]; then
    echo "Видаляємо сервіс: $SERVICE_PATH"
    rm -f $SERVICE_PATH
fi

if [[ -f $TIMER_PATH ]]; then
    echo "Видаляємо таймер: $TIMER_PATH"
    rm -f $TIMER_PATH
fi

# Оновлюємо systemd
echo "Оновлюємо systemd..."
systemctl daemon-reload

echo "Видалення завершено!"
