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

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(message)s")

GAIANET_URL = 'https://${node_address}.gaia.domains/v1/chat/completions'
GPT_URL = 'https://${DOM}.gaia.domains/v1/chat/completions'
GREEN = "\033[32m"
RESET = "\033[0m"

class DualAPIClient:
    def __init__(self):
        self.previous_question = None  

    def _send_request(self, url, message):
        headers = {'accept': 'application/json', 'Content-Type': 'application/json'}
        data = {"messages": [{"role": "system", "content": "You answer with 1 short phrase"}, {"role": "user", "content": message}]}

        try:
            response = requests.post(url, headers=headers, json=data)
            return response.json() if response.status_code == 200 else {"error": response.status_code, "message": response.text}
        except requests.exceptions.RequestException as e:
            return {"error": "network_error", "message": str(e)}

    def send_gpt_request(self, user_message):
        self.previous_question = user_message if not self.previous_question else f"{user_message} + 'your answer: {self.previous_question}'"
        return self._send_request(GPT_URL, self.previous_question)

    def send_custom_request(self, user_message):
        return self._send_request(GAIANET_URL, user_message)

client = DualAPIClient()

initial_question = "Let's go tell about China!"
gpt_response = client.send_gpt_request(initial_question)

while True:
    print(f'\n{GREEN}' + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()) + f" [Запит GPT]:{RESET}")
    gpt_answer = client.send_gpt_request(initial_question).get("choices", [{}])[0].get("message", {}).get("content", "Error")

    print(gpt_answer)

    custom_response = client.send_custom_request(gpt_answer + ' Tell me a random theme to speak')

    print(f'\n{GREEN}' + time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()) + f" [Відповідь GaiaNet]:{RESET}")

    custom_answer = custom_response.get("choices", [{}])[0].get("message", {}).get("content", "Error")
    print(custom_answer)

    time.sleep(1)
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
