#!/bin/bash

# Масив шляхів до конфігів
configs=(
    "/root/gaianet"
    "/root/node-2"
    "/root/node-3"
    "/root/node-4"
    "/root/node-5"
    "/root/node-6"
    "/root/node-7"
    "/root/node-8"
    "/root/node-9"
)

# Цикл по кожному каталогу
for config in "${configs[@]}"; do
    if [[ -d "$config" ]]; then
        backup_dir="backup_$(basename "$config")"
        mkdir -p "$backup_dir"
        
        # Копіюємо необхідні файли, якщо вони існують
        [[ -d "$config/gaia-frp" ]] && cp -r "$config/gaia-frp" "$backup_dir/"
        [[ -f "$config/config.json" ]] && cp "$config/config.json" "$backup_dir/"
        [[ -f "$config/deviceid.txt" ]] && cp "$config/deviceid.txt" "$backup_dir/"
        [[ -f "$config/nodeid.json" ]] && cp "$config/nodeid.json" "$backup_dir/"

        # Знаходимо файл за шаблоном
        name=$(find "$config" -maxdepth 1 -type f -regextype posix-extended -regex ".*/([^/]*-){4}[^/]*" -printf "%f\n" -quit)
        [[ -n "$name" && -f "$config/$name" ]] && cp "$config/$name" "$backup_dir/"

        echo "Бекап для $config збережено в $backup_dir"
    else
        echo "Каталог $config не знайдено, пропускаємо..."
    fi
done

# Видалення
for config in "${configs[@]}"; do
    if [[ -d "$config" ]]; then
        rm -rf "$config"
        echo "Каталог $config видалено."
    else
        echo "Каталог $config не знайдено, пропускаємо..."
    fi
done
