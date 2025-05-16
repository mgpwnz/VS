#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Aztec Validator Daily Scheduler with Retry Logic
# -------------------------------------------------------------------
# Этот скрипт создаёт или обновляет:
# 1) Файл переменных ENV_FILE, если ещё не создан
# 2) systemd service-файл с политикой перезапуска (до 3 попыток)
# 3) systemd timer-файл для ежедневного запуска в указанное время
# -------------------------------------------------------------------

# --- Переменные ---
ENV_FILE="$HOME/.env_aztec-validator"
SERVICE_PATH="/etc/systemd/system/aztec-validator.service"
TIMER_PATH="/etc/systemd/system/aztec-validator.timer"

# -------------------------------------------------------------------
# Шаг 1. Загрузка или ввод обязательных переменных
# -------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo -n "Enter RPC URL: "
  read -r RPC_URL

  echo -n "Enter your Private Key (with or without 0x): "
  read -r YourPrivateKey
  if [[ "${YourPrivateKey:0:2}" != "0x" && "${YourPrivateKey:0:2}" != "0X" ]]; then
    YourPrivateKey="0x${YourPrivateKey}"
  fi

  echo -n "Enter your Address: "
  read -r YourAddress

  cat > "$ENV_FILE" <<EOF
RPC_URL=${RPC_URL}
YourPrivateKey=${YourPrivateKey}
YourAddress=${YourAddress}
EOF

  chmod 600 "$ENV_FILE"
  echo "✅ Переменные сохранены в $ENV_FILE"
  source "$ENV_FILE"
fi

# -------------------------------------------------------------------
# Шаг 2. Ввод времени запуска (Kyiv timezone)
# -------------------------------------------------------------------
echo -n "Enter run time (HH:MM:SS, Kyiv time): "
read -r RUN_TIME    # например 00:49:01

# ежедневное расписание: каждый день в указанное время
SCHEDULE="*-*-* ${RUN_TIME} Europe/Kyiv"

# -------------------------------------------------------------------
# Шаг 3. Проверка наличия CLI aztec
# -------------------------------------------------------------------
AZTEC_BIN=$(command -v aztec || true)
if [[ -z "$AZTEC_BIN" ]]; then
  echo "Error: 'aztec' binary not found in PATH" >&2
  exit 1
fi

# -------------------------------------------------------------------
# Шаг 4. Создание или обновление service-файла
# -------------------------------------------------------------------
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Daily one-shot run of aztec add-l1-validator
# Если в течение часа будет более 3 неудачных попыток, блокируем новые перезапуски
StartLimitIntervalSec=3600
StartLimitBurst=3

[Service]
Type=oneshot
User=root
# При неудаче — перезапустить (максимум 3 раза за StartLimitInterval)
Restart=on-failure
RestartSec=2s

EnvironmentFile=${ENV_FILE}
Environment=HOME=/root
WorkingDirectory=/root

ExecStart=${AZTEC_BIN} add-l1-validator \\
  --l1-rpc-urls "\${RPC_URL}" \\
  --private-key "\${YourPrivateKey}" \\
  --attester "\${YourAddress}" \\
  --proposer-eoa "\${YourAddress}" \\
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \\
  --l1-chain-id 11155111

StandardOutput=journal
StandardError=journal
EOF

echo "✅ Service unit written to ${SERVICE_PATH}"

# -------------------------------------------------------------------
# Шаг 5. Создание или обновление timer-файла
# -------------------------------------------------------------------
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Timer: daily run of aztec-validator.service at ${RUN_TIME} (Kyiv)

[Timer]
# ежедневный запуск
OnCalendar=${SCHEDULE}
# сохранять информацию о последних запусках через перезагрузку
Persistent=true
# явно связать с нашим service
Unit=aztec-validator.service

[Install]
WantedBy=timers.target
EOF

echo "✅ Timer unit written to ${TIMER_PATH}"

# -------------------------------------------------------------------
# Шаг 6. Перезагрузка systemd и включение таймера
# -------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now aztec-validator.timer

echo ""
echo "✅ Система запланирована:"
echo "    • Ежедневный запуск в ${RUN_TIME} (Kyiv)"
echo "    • До 3 попыток при ошибках (30s пауза)"
echo "    • Service: ${SERVICE_PATH}"
echo "    • Timer:   ${TIMER_PATH}"
