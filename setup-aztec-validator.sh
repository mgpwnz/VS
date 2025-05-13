#!/usr/bin/env bash
set -euo pipefail

# --- Шаг 1: ввод данных ---
echo -n "Enter RPC URL: "
read RPC_URL

echo -n "Enter your Private Key (with or without 0x): "
read YourPrivateKey
# Добавляем префикс 0x, если отсутствует
if [[ "${YourPrivateKey:0:2}" != "0x" && "${YourPrivateKey:0:2}" != "0X" ]]; then
  YourPrivateKey="0x${YourPrivateKey}"
fi

echo -n "Enter your Address: "
read YourAddress

# --- Проверка наличия aztec CLI ---
AZTEC_BIN=$(command -v aztec || true)
if [[ -z "$AZTEC_BIN" ]]; then
  echo "Error: 'aztec' binary not found in PATH" >&2
  exit 1
fi

# --- Пути к unit-файлам ---
SERVICE_PATH="/etc/systemd/system/aztec-validator.service"
TIMER_PATH="/etc/systemd/system/aztec-validator.timer"

# --- Шаг 2: создаём сервис с оболочкой для расширения переменных ---
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=One-shot run of aztec add-l1-validator

[Service]
Type=oneshot
# Переменные окружения передаются внутрь Bash
Environment=RPC_URL=$RPC_URL
Environment=YourPrivateKey=$YourPrivateKey
Environment=YourAddress=$YourAddress
ExecStart=/bin/bash -lc '$AZTEC_BIN add-l1-validator \
  --l1-rpc-urls "\"$RPC_URL\"" \
  --private-key "\"$YourPrivateKey\"" \
  --attester "\"$YourAddress\"" \
  --proposer-eoa "\"$YourAddress\"" \
  --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
  --l1-chain-id 11155111'
EOF

# --- Шаг 3: создаём таймер ---
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run aztec-validator.service at 2025-05-13 23:49

[Timer]
OnCalendar=2025-05-13 23:49:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- Шаг 4: перезагружаем systemd, включаем и стартуем таймер ---
systemctl daemon-reload
systemctl enable --now aztec-validator.timer

echo "✅ Файлы созданы и таймер запущен:"
echo "   • Service: $SERVICE_PATH"
echo "   • Timer:   $TIMER_PATH"
