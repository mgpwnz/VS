#!/usr/bin/env bash
set -euo pipefail

# --- Файл переменных ---
ENV_FILE="$HOME/.env_aztec-validator"

# --- Шаг 1: загрузка или ввод обязательных переменных ---
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo -n "Enter RPC URL: "
  read RPC_URL

  echo -n "Enter your Private Key (with or without 0x): "
  read YourPrivateKey
  if [[ "${YourPrivateKey:0:2}" != "0x" && "${YourPrivateKey:0:2}" != "0X" ]]; then
    YourPrivateKey="0x${YourPrivateKey}"
  fi

  echo -n "Enter your Address: "
  read YourAddress

  cat > "$ENV_FILE" <<EOF
RPC_URL=${RPC_URL}
YourPrivateKey=${YourPrivateKey}
YourAddress=${YourAddress}
EOF
  chmod 600 "$ENV_FILE"
  echo "✅ Переменные сохранены в $ENV_FILE"
fi

# --- Шаг 2: ввод даты и времени запуска по киевскому ---
echo -n "Enter run date (YYYY-MM-DD): "
read RUN_DATE  # например 2025-05-14

echo -n "Enter run time (HH:MM:SS): "
read RUN_TIME  # например 00:49:01

# формируем строку OnCalendar с указанием часового пояса Kyiv
SCHEDULE="${RUN_DATE} ${RUN_TIME} Europe/Kyiv"

# --- Шаг 3: проверка наличия CLI aztec ---
AZTEC_BIN=$(command -v aztec || true)
if [[ -z "$AZTEC_BIN" ]]; then
  echo "Error: 'aztec' binary not found in PATH" >&2
  exit 1
fi

# --- Пути к unit-файлам ---
SERVICE_PATH="/etc/systemd/system/aztec-validator.service"
TIMER_PATH="/etc/systemd/system/aztec-validator.timer"

# --- Шаг 4: создаём или обновляем service-файл ---
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=One-shot run of aztec add-l1-validator

[Service]
Type=oneshot
User=root
EnvironmentFile=$ENV_FILE
Environment=HOME=/root
WorkingDirectory=/root
SuccessExitStatus=1
ExecStart=$AZTEC_BIN add-l1-validator \
  --l1-rpc-urls "\${RPC_URL}" \
  --private-key "\${YourPrivateKey}" \
  --attester "\${YourAddress}" \
  --proposer-eoa "\${YourAddress}" \
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
  --l1-chain-id 11155111
StandardOutput=journal
StandardError=journal

EOF

# --- Шаг 5: создаём или обновляем timer-файл с timezone ---
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run aztec-validator.service at ${RUN_DATE} ${RUN_TIME} Kyiv time

[Timer]
OnCalendar=${SCHEDULE}
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- Шаг 6: перезагружаем systemd и включаем таймер ---
systemctl daemon-reload
systemctl enable --now aztec-validator.timer

# --- Финальное сообщение ---
echo "✅ Юниты обновлены и таймер запланирован:"  
echo "   • Env file:   ${ENV_FILE}"  
echo "   • Service:    ${SERVICE_PATH}"  
echo "   • Timer:      ${TIMER_PATH} (OnCalendar=${SCHEDULE})"
