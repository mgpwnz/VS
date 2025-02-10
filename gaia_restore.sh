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

# Видалення
for config in "${configs[@]}"; do
    if [[ -d "$config" ]]; then
        echo "Видаляємо файли з $config..."
        
        # Видалення файлів, якщо вони існують
        [[ -d "$config/gaia-frp" ]] && rm -r "$config/gaia-frp"
        [[ -f "$config/config.json" ]] && rm "$config/config.json"
        [[ -f "$config/deviceid.txt" ]] && rm "$config/deviceid.txt"
        [[ -f "$config/nodeid.json" ]] && rm "$config/nodeid.json"

        # Видалення файлу за шаблоном
        name=$(find "$config" -maxdepth 1 -type f -regextype posix-extended -regex ".*/([^/]*-){4}[^/]*" -printf "%f\n" -quit)
        [[ -n "$name" && -f "$config/$name" ]] && rm "$config/$name"
        
    else
        echo "Каталог $config не знайдено, пропускаємо..."
    fi
done

# Цикл по кожному каталогу для відновлення
for config in "${configs[@]}"; do
    backup_dir="backup_$(basename "$config")"

    if [[ -d "$backup_dir" ]]; then
        echo "Відновлюємо файли для $config з $backup_dir..."
        mkdir -p "$config"

        # Відновлення файлів, якщо вони є в бекапі
        [[ -d "$backup_dir/gaia-frp" ]] && cp -r "$backup_dir/gaia-frp" "$config/"
        [[ -f "$backup_dir/config.json" ]] && cp "$backup_dir/config.json" "$config/"
        [[ -f "$backup_dir/deviceid.txt" ]] && cp "$backup_dir/deviceid.txt" "$config/"
        [[ -f "$backup_dir/nodeid.json" ]] && cp "$backup_dir/nodeid.json" "$config/"

        # Відновлення файлу за шаблоном
        name=$(find "$backup_dir" -maxdepth 1 -type f -regextype posix-extended -regex ".*/([^/]*-){4}[^/]*" -printf "%f\n" -quit)
        [[ -n "$name" && -f "$backup_dir/$name" ]] && cp "$backup_dir/$name" "$config/"

        echo "Відновлення для $config завершено!"
    else
        echo "Бекап $backup_dir не знайдено, пропускаємо..."
    fi
done

