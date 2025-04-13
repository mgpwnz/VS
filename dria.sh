#!/bin/bash

# Ввід спільного GEMINI API ключа
read -p "Введи GEMINI API ключ: " API

# Список доступних моделей
MODELS_LIST=(
  "gemini-2.0-pro-exp-02-05"
  "gemini-2.0-flash"
  "gemini-1.5-pro-exp-0827"
  "gemini-1.5-pro"
  "gemini-1.5-flash"
  "gemini-1.0-pro"
  "gemma-2-2b-it"
)

# Початковий порт
PORT=4002

# Лічильник конфігурацій
INDEX=2

# Функція для перевірки, чи порт вільний
is_port_available() {
  ! lsof -iTCP:$1 -sTCP:LISTEN >/dev/null
}

while true; do
  echo ""
  read -p "Введи приватний ключ (або залиш порожнім для виходу): " PRIVATEKEY
  [[ -z "$PRIVATEKEY" ]] && echo "Вихід." && break

  # Пошук наступного доступного порту
  while ! is_port_available $PORT; do
    echo "Порт $PORT зайнятий, пробую наступний..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
  done

  SESSION_NAME="dria$INDEX"
  FILENAME=".env.$SESSION_NAME"

  # Перевірка чи вже існує tmux-сесія з таким ім’ям
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Tmux-сесія $SESSION_NAME вже існує, пропускаємо."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  # Вибір випадкових моделей
  COUNT=$((RANDOM % 3 + 1))
  SELECTED_MODELS=$(shuf -e "${MODELS_LIST[@]}" -n "$COUNT" | paste -sd "," -)

  # Створення .env файлу
  cat > "$FILENAME" <<EOF
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

  echo "Конфігурацію збережено в $FILENAME"

  # Створення tmux-сесії та запуск з додаванням PATH
  tmux new-session -d -s "$SESSION_NAME" "export PATH=\"/root/.dria/bin:\$PATH\" && dkn-compute-launcher --profile $SESSION_NAME start"
  echo "Сесія $SESSION_NAME запущена в tmux."

  # Збільшуємо порт та індекс
  PORT=$((PORT + 1))
  INDEX=$((INDEX + 1))
done
