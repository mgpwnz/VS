#!/bin/bash

set -e

echo "📦 Installing DRIA Telegram Bot..."

# === Configuration ===
APP_DIR="/opt/dria_bot"
ENV_FILE="$APP_DIR/.env"
SERVICE_FILE="/etc/systemd/system/dria-bot.service"
PYTHON_BIN="/usr/bin/python3"
VENV_DIR="$APP_DIR/venv"

# === Create user if needed ===
if ! id "driauser" &>/dev/null; then
  echo "👤 Creating system user 'driauser'..."
  adduser --disabled-password --gecos "" driauser
fi

# === Prepare directories ===
mkdir -p "$APP_DIR"
mkdir -p "/home/driauser/dria_stats"
chown -R driauser:driauser /home/driauser/dria_stats
chmod 700 /home/driauser/dria_stats

# === Check or create .env ===
if [[ -f "$ENV_FILE" ]]; then
  echo "📄 .env file already exists. Skipping token input."
else
  read -p "🔐 Enter your Telegram BOT TOKEN: " BOT_TOKEN
  read -p "👤 Enter your Telegram user ID (AUTHORIZED_USER_ID): " TG_ID

  cat > "$ENV_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
AUTHORIZED_USER_ID=$TG_ID
STATS_DIR=/home/driauser/dria_stats
EOF

  chown driauser:driauser "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

# === Setup virtual environment ===
echo "🐍 Setting up Python venv..."
apt update && apt install -y python3 python3-venv
cd "$APP_DIR"
$PYTHON_BIN -m venv venv
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install python-telegram-bot python-dotenv

# === Write dria_bot.py ===
cat > "$APP_DIR/dria_bot.py" <<'EOF'
# -*- coding: utf-8 -*-
import os
import json
import locale
from datetime import datetime, timezone
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, CallbackQueryHandler, ContextTypes

# === Load config ===
load_dotenv(".env")
BOT_TOKEN = os.getenv("BOT_TOKEN")
AUTHORIZED_USER_ID = int(os.getenv("AUTHORIZED_USER_ID"))
STATS_DIR = os.getenv("STATS_DIR", "/home/driauser/dria_stats")
DATA_TIMEOUT_MINUTES = 10

# === Emoji switch ===
LANG = os.environ.get("LANG", "")
use_emoji = not LANG.startswith("C")

# === Check user ===
def is_authorized(user_id):
    return user_id == AUTHORIZED_USER_ID

# === Load JSON data ===
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

# === Format output with Total Points ===
def format_stats(stats):
    """
    Summarize DRIA points per server without listing every node,
    to avoid too-long messages.
    """
    lines = []
    now = datetime.now(timezone.utc)
    total_points = 0
    total_nodes = 0

    # Iterate over each server hostname
    for hostname in sorted(stats):
        host_data = stats[hostname]
        pts_dict = host_data.get("points", {})

        # Count how many nodes reported data
        node_count = len(pts_dict)

        # Sum only non-negative point values
        host_sum = sum(v for v in pts_dict.values() if isinstance(v, (int, float)) and v >= 0)
        total_points += host_sum
        total_nodes += node_count

        # Parse timestamp and compute “freshness”
        ts_str = host_data.get("timestamp", "")
        try:
            ts = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            age_minutes = (now - ts).total_seconds() / 60
            status = "✅" if age_minutes <= DATA_TIMEOUT_MINUTES else "⚠️"
            ts_display = ts.strftime("%Y-%m-%d %H:%M UTC")
        except Exception:
            status = "⚠️"
            ts_display = "UNKNOWN"

        # Build one line per server: hostname, node count, sum, timestamp, status
        lines.append(f"🖥 *{hostname}* — {node_count} nodes, {host_sum} points ({ts_display}) {status}")

    # Add a blank line and then overall totals
    lines.append("")
    lines.append(f"📊 *Servers:* {len(stats)}, *Total Nodes:* {total_nodes}, *Total Points:* *{total_points}*")

    return "\n".join(lines) or "No data found."

# === Bot handlers ===
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_authorized(update.effective_user.id):
        await update.message.reply_text("⛔️ Access denied.")
        return
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("📊 Show DRIA Points", callback_data="get_points")]
    ])
    await update.message.reply_text("Click the button below:", reply_markup=keyboard)

async def handle_button(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    if not is_authorized(query.from_user.id):
        await query.answer("⛔️ Access denied", show_alert=True)
        return
    await query.answer()
    stats = load_stats()
    await query.edit_message_text(format_stats(stats), parse_mode="Markdown")

# === Start ===
if __name__ == "__main__":
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_button, pattern="get_points"))
    print("✅ Bot is running")
    app.run_polling()
EOF

chown -R driauser:driauser "$APP_DIR"

# === Create systemd service ===
echo "🔧 Creating systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=DRIA Telegram Bot
After=network.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python dria_bot.py
Restart=always
User=driauser
EnvironmentFile=$ENV_FILE

[Install]
WantedBy=multi-user.target
EOF

# === Start bot ===
echo "🚀 Starting bot with systemd..."
systemctl daemon-reload
systemctl enable --now dria-bot.service

echo "✅ Bot installed and running!"
echo "📟 Check logs: journalctl -u dria-bot.service -f"
