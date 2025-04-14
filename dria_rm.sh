#!/bin/bash

echo "🛑 Зупиняємо тільки dria1, dria2... сервіси..."
systemctl list-units --type=service | grep -oE '^dria[0-9]+\.service' | xargs -r -I {} systemctl stop {}

echo "❌ Вимикаємо з автозапуску..."
systemctl list-unit-files | grep -oE '^dria[0-9]+\.service' | xargs -r -I {} systemctl disable {}

echo "🗑 Видаляємо .service файли..."
find /etc/systemd/system/ -regextype posix-extended -regex '.*/dria[0-9]+\.service' -exec rm -f {} \;

echo "🧹 Перезавантаження systemd..."
systemctl daemon-reload

echo "✅ Готово."
