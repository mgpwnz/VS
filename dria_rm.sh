#!/bin/bash

echo "🛑 Зупиняємо всі dria сервіси..."
systemctl list-units --type=service | grep dria | awk '{print $1}' | xargs -I {} systemctl stop {}

echo "❌ Вимикаємо з автозапуску..."
systemctl list-unit-files | grep dria | awk '{print $1}' | xargs -I {} systemctl disable {}

echo "🗑 Видаляємо .service файли..."
find /etc/systemd/system/ -name "dria*.service" -exec rm -f {} \;

echo "🧹 Перезавантаження systemd..."
systemctl daemon-reload

echo "✅ Готово."
