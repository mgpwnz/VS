#!/bin/bash

set -e

echo "🧹 Starting full DRIA cleanup..."

# === DRIA Bot variables ===
BOT_APP_DIR="/opt/dria_bot"
BOT_SERVICE_FILE="/etc/systemd/system/dria-bot.service"
BOT_USER="driauser"
BOT_STATS_DIR="/home/$BOT_USER/dria_stats"

# === DRIA Update script variables ===
UPDATE_SCRIPT="/root/update_points.sh"
UPDATE_SERVICE="/etc/systemd/system/dria-update.service"
UPDATE_TIMER="/etc/systemd/system/dria-update.timer"
UPDATE_ENV="/root/.dria_env"

# === 1. Stop and remove DRIA bot ===
if systemctl list-units --full -all | grep -q "dria-bot.service"; then
  echo "⛔️ Stopping and removing DRIA bot service..."
  systemctl stop dria-bot.service || true
  systemctl disable dria-bot.service || true
  rm -f "$BOT_SERVICE_FILE"
fi

echo "🗑 Removing DRIA bot files..."
rm -rf "$BOT_APP_DIR"
rm -rf "$BOT_STATS_DIR"

# === 2. Remove driauser if exists ===
if id "$BOT_USER" &>/dev/null; then
  echo "👤 Deleting user '$BOT_USER'..."
  userdel -r "$BOT_USER" || true
fi

# === 3. Remove DRIA auto-update service and script ===
if systemctl list-units --full -all | grep -q "dria-update.timer"; then
  echo "⛔️ Stopping and removing update service & timer..."
  systemctl stop dria-update.timer || true
  systemctl disable dria-update.timer || true
fi
rm -f "$UPDATE_SERVICE" "$UPDATE_TIMER"
rm -f "$UPDATE_SCRIPT"
rm -f "$UPDATE_ENV"

# === Reload systemd ===
systemctl daemon-reload

echo "✅ All DRIA components successfully removed!"
