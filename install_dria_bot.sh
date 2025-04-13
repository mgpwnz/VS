#!/bin/bash

echo "📦 Встановлення DRIA Telegram-бота..."

# 1. Параметри
APP_DIR="/opt/dria_bot"
ENV_FILE="$APP_DIR/.env"
SERVICE_FILE="/etc/systemd/system/dria-bot.service"
PYTHON_BIN="/usr/bin/python3"

# 2. Створення користувача
echo "👤 Створюємо користувача 'driauser'..."
id -u driauser &>/dev/null || adduser --disabled-password --gecos "" driauser

# 3. Створення директорій
mkdir -p "$APP_DIR"
mkdir -p "/home/driauser/dria_stats"
chown -R driauser:driauser /home/driauser/dria_stats
chmod 700 /home/driauser/dria_stats

# 4. Запит налаштувань
read -p "🔐 Введи Telegram BOT TOKEN: " BOT_TOKEN
read -p "👤 Введи твій Telegram user ID: " TG_ID

# 5. Збереження .env
cat > "$ENV_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
AUTHORIZED_USER_ID=$TG_ID
STATS_DIR=/home/driauser/dria_stats
EOF

# 6. Встановлення Python та залежностей
apt update
apt install -y python3 python3-pip
pip3 install python-telegram-bot python-dotenv

# 7. Завантаження коду бота
cat > "$APP_DIR/dria_bot.py" <<'EOF'
# -*- coding: utf-8 -*-
import os
import json
from datetime import datetime, timezone
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes

# === Load .env config ===
load_dotenv(".env")
BOT_TOKEN = os.getenv("BOT_TOKEN")
AUTHORIZED_USER_ID = int(os.getenv("AUTHORIZED_USER_ID"))
STATS_DIR = os.getenv("STATS_DIR", "/home/driauser/dria_stats")
DATA_TIMEOUT_MINUTES = 10

# === Access control ===
def is_authorized(user_id):
    return user_id == AUTHORIZED_USER_ID

# === Load all .json stats ===
def load_stats():
    data = {}
    for file in os.listdir(STATS_DIR):
        if not file.endswith(".json"):
            continue
        try:
            with open(os.path.join(STATS_DIR, file)) as f:
                server_data = json.load(f)
                hostname = server_data.get("hostname", "unknown")
                timestamp = server_data.get("timestamp", "")
                points = server_data.get("points", {})
                data[hostname] = {
                    "timestamp": timestamp,
                    "points": points
                }
        except Exception:
            continue
    return data

# === Format message for Telegram ===
def format_stats(stats):
    lines = []
    now = datetime.now(timezone.utc)

    for hostname in sorted(stats):
        ts_str = stats[hostname].get("timestamp", "")
        try:
            ts = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            age_minutes = (now - ts).total_seconds() / 60
            status_emoji = "✅" if age_minutes <= DATA_TIMEOUT_MINUTES else "⚠️"
            ts_display = ts.strftime("%Y-%m-%d %H:%M UTC")
        except Exception:
            ts_display = "UNKNOWN"
            status_emoji = "⚠️"

        lines.append(f"🖥 *{hostname}* ({ts_display}) {status_emoji}")
        for node, pts in sorted(stats[hostname]["points"].items()):
            if pts >= 0:
                lines.append(f"  └ {node}: *{pts}* Points")
            else:
                lines.append(f"  └ {node}: ❌ Error")
    return "\n".join(lines) or "No data found."

# === /start command ===
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update.effective_user.id):
        await update.message.reply_text("⛔️ Access denied.")
        return
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("📊 Show DRIA Points", callback_data="get_points")]
    ])
    await update.message.reply_text("Click the button below:", reply_markup=keyboard)

# === Handle button click ===
async def handle_button(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    if not is_authorized(query.from_user.id):
        await query.answer("⛔️ Access denied", show_alert=True)
        return
    await query.answer()
    stats = load_stats()
    await query.edit_message_text(format_stats(stats), parse_mode="Markdown")

# === Start bot ===
if __name__ == "__main__":
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_button, pattern="get_points"))
    print("✅ Bot is running")
    app.run_polling()

EOF

chown -R driauser:driauser "$APP_DIR"

# 8. Створення systemd сервісу
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=DRIA Telegram Bot
After=network.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_BIN dria_bot.py
Restart=always
User=driauser
EnvironmentFile=$ENV_FILE

[Install]
WantedBy=multi-user.target
EOF

# 9. Активуємо
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now dria-bot.service

echo "✅ Telegram бот встановлено та запущено!"
echo "ℹ️ Перевірити лог: journalctl -u dria-bot.service -f"
