#!/bin/bash

function="install"

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
        -h|--help)
            echo "Usage: $0 [-in|--install] [-un|--uninstall]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

configs=(
    "/root/gaianet/config.json"
    "/root/node-2/config.json"
    "/root/node-3/config.json"
    "/root/node-4/config.json"
    "/root/node-5/config.json"
    "/root/node-6/config.json"
    "/root/node-7/config.json"
    "/root/node-8/config.json"
    "/root/node-9/config.json"
)

install() {
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "Помилка: Немає доступних конфігураційних файлів."
        exit 1
    fi

    for config_file in "${configs[@]}"; do
        if [[ ! -f "$config_file" ]]; then
            echo "Файл конфігурації не знайдено: $config_file"
            continue
        fi

        node_name=$(basename "$(dirname "$config_file")")
        node_address=$(grep -oP '"address": "\K[^"]+' "$config_file")
        if [[ -z "$node_address" ]]; then
            echo "Не вдалося знайти NODE-ADDRESS у $config_file"
            continue
        fi

        echo "Витягнуто NODE-ADDRESS для $node_name: $node_address"

        while true; do
            read -p "Enter your DOMAIN: " DOM
            if [[ -n "$DOM" && "$DOM" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                break
            else
                echo "Невірний формат DOMAIN. Спробуйте ще раз."
            fi
        done

        script_path="/usr/local/bin/random_chat_with_faker_${node_name}.py"
        service_name="gaia_chat_${node_name}.service"

        cat << EOF > "$script_path"
import requests
import json
import time
import logging


log_file = f'/var/log/chat_log_${node_name}.txt' 
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(message)s")
file_handler = logging.FileHandler(log_file)
file_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(message)s')
file_handler.setFormatter(formatter)
logging.getLogger().addHandler(file_handler)

gaianetLink = 'https://${node_address}.gaia.domains/v1/chat/completions'

GREEN = "\033[32m"
RESET = "\033[0m"

class DualAPIClient:
    def __init__(self, gpt_config, custom_config):
        self.gpt_config = gpt_config
        self.custom_config = custom_config
        self.previous_question = None  # Переменная для хранения предыдущего вопроса

    def _send_request(self, config):
        try:
            logging.info(f"Відправка запиту: {json.dumps(config['data'], indent=2)}")  # Логування запиту
            response = requests.post(config['url'], headers=config['headers'], data=json.dumps(config['data']))
            if response.status_code == 200:
                logging.info(f"Отримано відповідь: {response.json()}")  # Логування відповіді
                return response.json()
            else:
                # Возвращаем код ошибки и текст ответа сервера
                logging.error(f"Помилка запиту: {response.status_code} - {response.text}")
                return {
                    "error": response.status_code,
                    "message": response.text
                }
        except requests.exceptions.RequestException as e:
            # Ловим виключення мережі
            logging.error(f"Помилка мережі: {str(e)}")
            return {
                "error": "network_error",
                "message": str(e)
            }

    def send_gpt_request(self, user_message):
        if self.previous_question:
            usr_message = f"{user_message} + 'your answer: {self.previous_question}'"
        else:
            usr_message = user_message

        self.gpt_config['data']['messages'][1]['content'] = usr_message
        response = self._send_request(self.gpt_config)

        if "error" not in response:
            self.previous_question = self.extract_answer(response)

        return response

    def send_custom_request(self, user_message):
        self.custom_config['data']['messages'][1]['content'] = user_message
        return self._send_request(self.custom_config)

    def extract_answer(self, response):
        if "error" in response:
            return f"Error: {response['error']} - {response['message']}"
        return response.get('choices', [{}])[0].get('message', {}).get('content', '')


gpt_config = {
    'url': f'https://${DOM}.gaia.domains/v1/chat/completions',
    'headers': {
        'accept': 'application/json',
        'Content-Type': 'application/json'
    },
    'data': {
        "messages": [
            {"role": "system", "content": 'You answer with 1 short phrase'},
            {"role": "user", "content": ""}  # Тут можна передати повідомлення користувача
        ]
    }
}

gaianet_config = {
    'url': f'https://${DOM}.gaia.domains/v1/chat/completions',
    'headers': {
        'accept': 'application/json',
        'Content-Type': 'application/json'
    },
    'data': {
        "messages": [
            {"role": "system", "content": "You answer with 1 short phrase"},
            {"role": "user", "content": ""}  # Тут також передається повідомлення
        ]
    }
}

client = DualAPIClient(gpt_config, gaianet_config)

initial_question = "Let's go tell about China!"
gpt_response = client.send_gpt_request(initial_question)

logging.info(f"Запит до GPT: {initial_question}")  # Логування початку діалогу

while True:
    logging.info(f"Запит від GPT: {gpt_response.get('choices', [{}])[0].get('message', {}).get('content', '')}")
    print(f'\n{GREEN}' + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()) + f" [Вопрос от GPT]:{RESET}")

    if "error" in gpt_response:
        logging.error(f"GPT Request Error {gpt_response['error']}: {gpt_response['message']}")
        gpt_answer = "Error occurred. Please retry."
    else:
        gpt_answer = client.extract_answer(gpt_response).replace('\n', ' ')
        logging.info(f"Відповідь GPT: {gpt_answer}")
        print(f"GPT: {gpt_answer}")  # Виведення відповіді в консоль

    custom_response = client.send_custom_request(gpt_answer + ' Tell me a random theme to speak')

    logging.info(f"Відправка запиту GaiaNet: {gpt_answer + ' Tell me a random theme to speak'}")
    print(f'\n{GREEN}' + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()) + f" [Ответ GaiaNet]:{RESET}")

    if "error" in custom_response:
        logging.error(f"GaiaNet Request Error {custom_response['error']}: {custom_response['message']}")
        custom_answer = "Error occurred. Please retry."
    else:
        custom_answer = client.extract_answer(custom_response).replace('\n', ' ')
        logging.info(f"Відповідь GaiaNet: {custom_answer}")
        print(f"GaiaNet: {custom_answer}")  # Виведення відповіді в консоль

    gpt_response = client.send_gpt_request(custom_answer)
    time.sleep(10)  # Затримка 10 секунд між запитами

EOF

        chmod +x "$script_path"

        service_file="/etc/systemd/system/$service_name"
        if [[ ! -f "$service_file" ]]; then
            cat << EOF > "$service_file"
[Unit]
Description=Gaia Chat Service for $node_name
After=network.target

[Service]
ExecStart=/usr/bin/python3 $script_path
Restart=always
User=root
StandardOutput=append:/var/log/gaia_chat_${node_name}.log
StandardError=append:/var/log/gaia_chat_${node_name}_error.log

[Install]
WantedBy=multi-user.target
EOF
        fi

        systemctl daemon-reload
        systemctl enable --now "$service_name"

        echo "Служба $service_name успішно запущена."
    done
}

uninstall() {
    for config_file in "${configs[@]}"; do
        node_name=$(basename "$(dirname "$config_file")")
        service_name="gaia_chat_${node_name}.service"
        script_path="/usr/local/bin/random_chat_with_faker_${node_name}.py"

        if systemctl is-active --quiet "$service_name"; then
            systemctl stop "$service_name"
            systemctl disable "$service_name"
        fi

        rm -f "/etc/systemd/system/$service_name"
        rm -f "$script_path"

        echo "Службу $service_name і скрипт $script_path видалено."
    done

    systemctl daemon-reload
}

apt install wget -y &>/dev/null
cd
$function
