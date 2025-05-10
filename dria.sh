#!/bin/bash

MODELS_LIST="gemini-2.0-flash"
PORT=4001
INDEX=1

CONFIG_DIR="/root/.dria/dkn-compute-launcher"
LOG_DIR="/var/log/dria"
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

is_port_available() {
  ! lsof -iTCP:$1 -sTCP:LISTEN >/dev/null
}

RELOAD_NEEDED=false

while true; do
  SESSION_NAME="dria$INDEX"
  ENV_PATH="$CONFIG_DIR/.env.$SESSION_NAME"
  SERVICE_PATH="/etc/systemd/system/$SESSION_NAME.service"
  LOG_PATH="$LOG_DIR/$SESSION_NAME.log"

  # Пропуск, якщо є і .service, і .env
  if [[ -f "$SERVICE_PATH" && -f "$ENV_PATH" ]]; then
    echo "⚠️  Сервіс $SESSION_NAME та конфігурація $ENV_PATH вже існують. Пропускаємо..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  # Якщо існує .env, пропонуємо дії
  if [[ -f "$ENV_PATH" ]]; then
    echo "⚠️  Конфігурація $ENV_PATH існує."
    read -p "Виберіть дію: (O)verwrite / (U)se existing / (S)kip [O/U/S]: " ACTION
    ACTION=${ACTION^^}
    case "$ACTION" in
      S)
        echo "⏭ Пропущено $SESSION_NAME"
        PORT=$((PORT + 1))
        INDEX=$((INDEX + 1))
        continue
        ;;
      U)
        echo "✅ Використано існуючий .env"
        CONFIGURED=false
        ;;
      O)
        echo "🔁 Перезаписуємо конфігурацію..."
        read -p "Введіть приватний ключ: " PRIVATEKEY
        read -p "Введіть GEMINI API ключ: " API
        CONFIGURED=true
        ;;
      *)
        echo "Невірний вибір. Пропуск."
        PORT=$((PORT + 1))
        INDEX=$((INDEX + 1))
        continue
        ;;
    esac
  else
    # Створення нового .env
    echo
    read -p "Введи приватний ключ (або пустий для виходу): " PRIVATEKEY
    [[ -z "$PRIVATEKEY" ]] && echo "Вихід." && break
    read -p "Введи GEMINI API ключ: " API
    CONFIGURED=true
  fi

  # Якщо потрібна нова або оновлена конфігурація
  if [[ "$CONFIGURED" == true ]]; then
    # Знаходимо вільний порт
    while ! is_port_available "$PORT"; do
      echo "Порт $PORT зайнятий — пробуємо $((PORT + 1))"
      PORT=$((PORT + 1))
      INDEX=$((INDEX + 1))
      SESSION_NAME="dria$INDEX"
      ENV_PATH="$CONFIG_DIR/.env.$SESSION_NAME"
      SERVICE_PATH="/etc/systemd/system/$SESSION_NAME.service"
      LOG_PATH="$LOG_DIR/$SESSION_NAME.log"
    done

    # Записуємо .env
    cat > "$ENV_PATH" <<EOF
## DRIA ##
DKN_WALLET_SECRET_KEY=$PRIVATEKEY
DKN_MODELS=$MODELS_LIST
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

    echo "✅ Конфігурація записана: $ENV_PATH"
  fi

  # Створення або оновлення сервісу
  if [[ -f "$SERVICE_PATH" ]]; then
    if [[ "$CONFIGURED" == true ]]; then
      echo "🔄 Оновлюємо сервіс $SESSION_NAME"
      systemctl daemon-reload
      systemctl restart "$SESSION_NAME"
      echo "✅ Сервіс $SESSION_NAME перезапущено"
    else
      echo "⏭ Сервіс $SESSION_NAME існує, без змін"
    fi
  else
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Dria Compute Node - $SESSION_NAME
After=network.target

[Service]
Type=forking
EnvironmentFile=$ENV_PATH
ExecStart=/root/.dria/bin/dkn-compute-launcher --profile $SESSION_NAME start
WorkingDirectory=/root
User=root
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOF

    echo "✅ Сервіс створено: $SERVICE_PATH"
    RELOAD_NEEDED=true
  fi

  # Підготовка до наступної ітерації
  PORT=$((PORT + 1))
  INDEX=$((INDEX + 1))
  unset CONFIGURED
done

# Після циклу: завантаження нових сервісів
if $RELOAD_NEEDED; then
  echo "🔄 Оновлення systemd..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl list-units --type=service | grep dria
  read -p "Запустити всі нові сервіси зараз? [y/N]: " START_ALL
  if [[ "$START_ALL" =~ ^[Yy]$ ]]; then
    systemctl list-unit-files | grep dria | awk '{print $1}' | xargs -I {} systemctl enable --now {}
  fi
fi
echo "✅ Готово."