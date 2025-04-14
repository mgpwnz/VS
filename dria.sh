#!/bin/bash

MODELS_LIST="gemini-2.0-flash,gemini-1.5-flash"

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
  echo ""
  read -p "Введи приватний ключ (або залиш порожнім для виходу): " PRIVATEKEY
  [[ -z "$PRIVATEKEY" ]] && echo "Вихід." && break

  read -p "Введи GEMINI API ключ: " API

  while ! is_port_available $PORT; do
    echo "Порт $PORT зайнятий, шукаємо далі..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
  done

  SESSION_NAME="dria$INDEX"
  ENV_PATH="$CONFIG_DIR/.env.$SESSION_NAME"
  SERVICE_PATH="/etc/systemd/system/$SESSION_NAME.service"
  LOG_PATH="$LOG_DIR/$SESSION_NAME.log"

  if systemctl list-units --type=service --all | grep -q "$SESSION_NAME.service"; then
    echo "⚠️  Сервіс $SESSION_NAME вже існує. Пропускаємо..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  if [[ -f "$ENV_PATH" ]]; then
    echo "⚠️  Конфігурація $ENV_PATH вже існує."
    read -p "Вибери дію: (O)verwrite / (U)se existing / (S)kip [O/U/S]: " ACTION
    ACTION=${ACTION^^}
    if [[ "$ACTION" == "S" ]]; then
      echo "⏭ Пропущено $SESSION_NAME"
      PORT=$((PORT + 1))
      INDEX=$((INDEX + 1))
      continue
    elif [[ "$ACTION" == "U" ]]; then
      echo "✅ Використано існуючий .env"
    else
      echo "🔁 Перезаписуємо конфігурацію..."
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
    fi
  else
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
  fi

  echo "✅ Конфігурація: $ENV_PATH"

  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Dria Compute Node - $SESSION_NAME
After=network.target

[Service]
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

  echo "✅ Сервіс: $SERVICE_PATH"
  RELOAD_NEEDED=true

  PORT=$((PORT + 1))
  INDEX=$((INDEX + 1))
done

if $RELOAD_NEEDED; then
  echo "🔄 Оновлення systemd..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl list-units --type=service | grep dria
  read -p "Хочеш запустити всі створені сервіси зараз? [y/N]: " START_ALL
  if [[ "$START_ALL" =~ ^[Yy]$ ]]; then
    systemctl list-unit-files | grep dria | awk '{print $1}' | xargs -I {} systemctl enable --now {}
  fi
fi
