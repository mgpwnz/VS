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

  # 1) Якщо вже є і сервіс, і .env → пропускаємо цю сесію
  if systemctl list-units --type=service --all | grep -q "$SESSION_NAME.service" && [[ -f "$ENV_PATH" ]]; then
    echo "⚠️  Сервіс $SESSION_NAME та конфігурація $ENV_PATH вже існують. Пропускаємо..."
    PORT=$((PORT + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  # 2) Якщо .env існує, пропонуємо дії
  if [[ -f "$ENV_PATH" ]]; then
    echo "⚠️  Конфігурація $ENV_PATH вже існує."
    read -p "Вибери дію: (O)verwrite / (U)se existing / (S)kip [O/U/S]: " ACTION
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
        CONFIGURED=true
        ;;
      O)
        echo "🔁 Перезаписуємо конфігурацію..."
        read -p "Введи приватний ключ: " PRIVATEKEY
        read -p "Введи GEMINI API ключ: " API
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
    # 3) Якщо .env немає — збираємо дані для нової конфігурації
    echo
    read -p "Введи приватний ключ (або пустий для виходу): " PRIVATEKEY
    [[ -z "$PRIVATEKEY" ]] && echo "Вихід." && break
    read -p "Введи GEMINI API ключ: " API
    CONFIGURED=true
  fi

  # 4) Підбираємо вільний порт (якщо ми щойно ввели дані)
  if [[ "$CONFIGURED" == true ]]; then
    while ! is_port_available $PORT; do
      echo "Порт $PORT зайнятий — пробуємо $((PORT+1))"
      PORT=$((PORT + 1))
      INDEX=$((INDEX + 1))
      SESSION_NAME="dria$INDEX"
      ENV_PATH="$CONFIG_DIR/.env.$SESSION_NAME"
      SERVICE_PATH="/etc/systemd/system/$SESSION_NAME.service"
      LOG_PATH="$LOG_DIR/$SESSION_NAME.log"
    done

    # 5) Записуємо або перезаписуємо .env
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

  # 6) Створюємо або оновлюємо сервіс
  if systemctl list-units --type=service --all | grep -q "$SESSION_NAME.service"; then
    if [[ "$CONFIGURED" == true ]]; then
      echo "🔄 Оновлюємо сервіс $SESSION_NAME"
      systemctl daemon-reload
      systemctl restart "$SESSION_NAME"
    else
      echo "⏭ Сервіс $SESSION_NAME існує, змін не потрібно"
    fi
  else
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
    echo "✅ Сервіс створено: $SERVICE_PATH"
    RELOAD_NEEDED=true
  fi

  # Готуємося до наступної ітерації
  PORT=$((PORT + 1))
  INDEX=$((INDEX + 1))
  unset CONFIGURED
done

# 7) Завантажуємо нові юніти лише один раз після циклу
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
echo "✅ Готово. Всі сесії:"
systemctl list-units --type=service | grep dria
