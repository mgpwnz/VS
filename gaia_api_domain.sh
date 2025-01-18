#!/bin/bash
# Default variables
function="install"
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
    # API key
    read -p "Enter your API: " GAPI
    read -p "Enter your DOMAIN: " DOM
    
if [[ -z "$GAPI" || -z "$DOM" ]]; then
    echo "API або DOMAIN не були введені. Будь ласка, спробуйте ще раз."
    exit 1
fi
    # Оновлення та встановлення необхідних пакетів
    echo "Оновлення пакетів..."
    apt update && apt install -y python3-pip

    # Встановлення бібліотек для Python
    echo "Встановлення бібліотек для Python..."
    #pip3 install requests faker tenacity
    pip3 install requests faker tenacity

    # Створення Python скрипта
    echo "Створення скрипта random_chat_with_faker.py..."
    cat << EOF > /usr/local/bin/random_chat_with_faker.py
import requests
import random
import logging
import time
from faker import Faker
from datetime import datetime
from tenacity import retry, stop_after_attempt, wait_fixed

node_url = "https://${DOM}.gaia.domains/v1/chat/completions"

faker = Faker()

api_key = "${GAPI}"
headers = {
    "accept": "application/json",
    "Content-Type": "application/json",
    "Authorization": f"Bearer {api_key}"
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

    delay = random.randint(480, 600)
    time.sleep(delay)
EOF

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

    systemctl daemon-reload
    systemctl start gaia_chat.service
    systemctl enable gaia_chat.service

    echo "Служба gaia_chat.service успішно запущена. Використовуйте 'journalctl -u gaia_chat.service -f' для перегляду журналу."
}

uninstall() {
    systemctl stop gaia_chat.service
    systemctl disable gaia_chat.service
    rm -f /usr/local/bin/random_chat_with_faker.py
    rm -f /etc/systemd/system/gaia_chat.service
    systemctl daemon-reload
    echo "Видалення завершено."
}

$function
