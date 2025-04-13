#!/bin/bash

# Ввід спільного GEMINI API ключа
read -p "Введи GEMINI API ключ: " API

# Список доступних моделей
MODELS_LIST=(
  "gemini-2.0-flash"
  "gemini-1.5-flash"
)

# Початковий порт
PORT=4002
INDEX=2

# Каталог конфігурацій
CONFIG_DIR="/root/.dria/dkn-compute-launcher"
mkdir -p "$CONFIG_DIR"

# Функція для перевірки, чи порт вільний
is_port_available() {
  ! lsof -iTCP:$1 -sTCP:LISTEN >/dev/null
}

while true; do
  echo ""
  read -p "Введи приватний ключ (або залиш порожнім для виходу): " PRIVATEKEY
  [[ -z "$PRIVATEKEY" ]] && echo "Вихід." && break

  # Знаходимо вільний порт
  while ! is_port_available $PORT; do
    echo "Порт $PORT зайнятий, шукаємо далі..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
  done

  SESSION_NAME="dria$INDEX"
  ENV_PATH="$CONFIG_DIR/.env.$SESSION_NAME"
  SERVICE_PATH="/etc/systemd/system/$SESSION_NAME.service"

  # Якщо сервіс вже існує — пропускаємо
  if systemctl list-units --type=service --all | grep -q "$SESSION_NAME.service"; then
    echo "Сервіс $SESSION_NAME вже існує. Пропускаємо..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  # Вибираємо випадкові моделі
  COUNT=$((RANDOM % 3 + 1))
  SELECTED_MODELS=$(shuf -e "${MODELS_LIST[@]}" -n "$COUNT" | paste -sd "," -)

  # Генерація .env файлу
  cat > "$ENV_PATH" <<EOF
## DRIA ##
DKN_WALLET_SECRET_KEY=$PRIVATEKEY
DKN_MODELS=$SELECTED_MODELS
DKN_P2P_LISTEN_ADDR=/ip4/0.0.0.0/tcp/$PORT
DKN_RELAY_NODES=
DKN_BOOTSTRAP_NODES=
DKN_BATCH_SIZE=

## Ollama (if used, optional) ##
OLLAMA_HOST=http://127.0.0.1
OLLAMA_PORT=11434
OLLAMA_AUTO_PULL=true

## Open AI (if used, required) ##
OPENAI_API_KEY=
## Gemini (if used, required) ##
GEMINI_API_KEY=$API
## Open Router (if used, required) ##
OPENROUTER_API_KEY=
## Serper (optional) ##
SERPER_API_KEY=
## Jina (optional) ##
JINA_API_KEY=

## Log levels
RUST_LOG=none
EOF

  echo "✅ Збережено: $ENV_PATH"

  # Генерація systemd-сервісу
  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Dria Compute Node - $SESSION_NAME
After=network.target

[Service]
EnvironmentFile=$ENV_PATH
ExecStart=/root/.dria/bin/dkn-compute-launcher --profile $SESSION_NAME start
Restart=on-failure
RestartSec=5
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

  echo "✅ Створено systemd сервіс: $SERVICE_PATH"

  # Перезавантажуємо systemd та запускаємо сервіс
  systemctl daemon-reload
  systemctl enable --now "$SESSION_NAME.service"

  echo "🚀 Сервіс $SESSION_NAME запущено (порт $PORT, моделі: $SELECTED_MODELS)"

  # Переходимо до наступного
  PORT=$((PORT + 1))
  INDEX=$((INDEX + 1))
done

