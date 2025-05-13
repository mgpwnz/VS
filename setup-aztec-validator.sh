#!/usr/bin/env bash
set -euo pipefail

# --- Шаг 1: ввод данных ---
echo -n "Enter RPC URL: "
read RPC_URL

echo -n "Enter your Private Key (with or without 0x): "
read YourPrivateKey
if [[ "${YourPrivateKey:0:2}" != "0x" && "${YourPrivateKey:0:2}" != "0X" ]]; then
  YourPrivateKey="0x${YourPrivateKey}"
fi

echo -n "Enter your Address: "
read YourAddress

# --- Шаг 2: ввод времени запуска ---
echo -n "Enter run time (YYYY-MM-DD HH:MM:SS): "
read SCHEDULE

# --- Шаг 3: сохраняем переменные в файле в домашнем каталоге ---
ENV_FILE="$HOME/.env_aztec-validator"
cat > "$ENV_FILE" <<EOF
RPC_URL=${RPC_URL}
YourPrivateKey=${YourPrivateKey}
YourAddress=${YourAddress}
EOF
chmod 600 "$ENV_FILE"

# --- Шаг 4: проверка aztec CLI ---
AZTEC_BIN=$(command -v aztec || true)
if [[ -z "$AZTEC_BIN" ]]; then
  echo "Error: 'aztec' binary not found in PATH" >&2
  exit 1
fi

# --- Пути к unit-файлам ---
SERVICE_PATH="/etc/systemd/system/aztec-validator.service"
TIMER_PATH="/etc/systemd/system/aztec-validator.timer"

# --- Шаг 5: создаём или обновляем сервис ---
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=One-shot run of aztec add-l1-validator

[Service]
Type=oneshot
User=root
EnvironmentFile=$ENV_FILE
Environment=HOME=/root
WorkingDirectory=/root
ExecStart=$AZTEC_BIN add-l1-validator \
  --l1-rpc-urls "${RPC_URL}" \
  --private-key "${YourPrivateKey}" \
  --attester "${YourAddress}" \
  --proposer-eoa "${YourAddress}" \
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
  --l1-chain-id 11155111
EOF

# --- Шаг 6: создаём или обновляем таймер с новым расписанием ---
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run aztec-validator.service at $SCHEDULE

[Timer]
OnCalendar=$SCHEDULE
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- Шаг 7: перезагружаем systemd и включаем таймер ---
systemctl daemon-reload
systemctl enable --now aztec-validator.timer

# --- Итоговое сообщение ---
echo "✅ Системные юниты обновлены и таймер запланирован:"  
echo "   • Env file:   ${ENV_FILE}"  
echo "   • Service:    ${SERVICE_PATH}"  
echo "   • Timer:      ${TIMER_PATH} (OnCalendar=${SCHEDULE})"
