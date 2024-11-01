#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
    break
    ;;
    esac
done


install() {
 # Шлях до файлу конфігурації
config_file="/root/gaianet/config.json"

# Перевірка наявності файлу конфігурації
if [[ ! -f "$config_file" ]]; then
    echo "Файл конфігурації не знайдено: $config_file"
    exit 1
fi

# Витягування NODE-ADDRESS з файлу конфігурації
node_address=$(grep -oP '"address": "\K[^"]+' "$config_file")

# Перевірка, чи було успішно витягнуто NODE-ADDRESS
if [[ -z "$node_address" ]]; then
    echo "Не вдалося знайти NODE-ADDRESS у файлі конфігурації."
    exit 1
fi

echo "Витягнуто NODE-ADDRESS: $node_address"

# Оновлення та встановлення необхідних пакетів
echo "Оновлення пакетів..."
sudo apt update && sudo apt install -y python3-pip

# Встановлення бібліотек для Python
echo "Встановлення бібліотек для Python..."
pip3 install requests faker tenacity --break-system-packages

# Створення Python скрипта з підставленою NODE-ADDRESS
echo "Створення скрипта random_chat_with_faker.py..."
cat << EOF > /usr/local/bin/random_chat_with_faker.py
import requests
import random
import logging
import time
from faker import Faker
from datetime import datetime
from tenacity import retry, stop_after_attempt, wait_fixed

node_url = "https://${node_address}.us.gaianet.network/v1/chat/completions"

faker = Faker()

headers = {
    "accept": "application/json",
    "Content-Type": "application/json"
}

logging.basicConfig(filename='/var/log/chat_log.txt', level=logging.INFO, format='%(asctime)s - %(message)s')

def log_message(node, message):
    logging.info(f"{node}: {message}")

@retry(stop=stop_after_attempt(3), wait=wait_fixed(5))
def send_message(node_url, message):
    try:
        response = requests.post(node_url, json=message, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.Timeout:
        print("Request timed out")
        logging.error("Request timed out")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Failed to get response from API: {e}")
        logging.error(f"Failed to get response from API: {e}")
        return None

def extract_reply(response):
    if response and 'choices' in response:
        return response['choices'][0]['message']['content']
    return "No reply"

while True:
    random_question = faker.sentence(nb_words=10)
    message = {
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": random_question}
        ]
    }

    question_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    response = send_message(node_url, message)
    reply = extract_reply(response)

    reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    log_message("Node replied", f"Q ({question_time}): {random_question} A ({reply_time}): {reply}")

    print(f"Q ({question_time}): {random_question}\nA ({reply_time}): {reply}")

    delay = random.randint(60, 180)
    time.sleep(delay)
EOF

# Надаємо права на виконання скрипту
chmod +x /usr/local/bin/random_chat_with_faker.py

# Створення systemd юніт-файлу
echo "Створення systemd юніт-файлу для служби gaia_chat.service..."
cat << EOF > /etc/systemd/system/gaia_chat.service
[Unit]
Description=Gaia Chat Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/random_chat_with_faker.py
Restart=always
User=root
StandardOutput=append:/var/log/gaia_chat.log
StandardError=append:/var/log/gaia_chat_error.log

[Install]
WantedBy=multi-user.target
EOF

# Перезавантаження systemd, запуск та включення служби
echo "Запуск та активація служби gaia_chat.service..."
sudo systemctl daemon-reload
sudo systemctl start gaia_chat.service
sudo systemctl enable gaia_chat.service

echo "Служба gaia_chat.service успішно запущена. Використовуйте 'journalctl -u gaia_chat.service -f' для перегляду журналу в реальному часі."
}

uninstall() {
  if [ ! -f "/usr/local/bin/random_chat_with_faker.py" ]; then
    echo "File not found"
    return
  fi

  read -r -p "Wipe all DATA? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY]) 
        sudo systemctl stop gaia_chat.service
        sudo systemctl disable gaia_chat.service
        sudo systemctl daemon-reload
        rm /usr/local/bin/random_chat_with_faker.py
        echo "Видалено"
        ;;
    *)
        echo "Canceled"
        return
        ;;
  esac
}

# Execute the selected function
sudo apt install wget -y &>/dev/null
cd
$function
