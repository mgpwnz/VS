#!/bin/bash

# Function to check if a command was successful
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}

# Stop and disable the systemd services
echo "Stopping and disabling services..."
systemctl stop shardeum-validator.service
check_command "Stopping shardeum-validator.service"
systemctl disable shardeum-validator.service
check_command "Disabling shardeum-validator.service"
systemctl stop shardeum-telegram-bot.service
check_command "Stopping shardeum-telegram-bot.service"
systemctl disable shardeum-telegram-bot.service
check_command "Disabling shardeum-telegram-bot.service"

# Remove the systemd service files
echo "Removing systemd service files..."
rm -f /etc/systemd/system/shardeum-validator.service
check_command "Removing shardeum-validator.service"
rm -f /etc/systemd/system/shardeum-telegram-bot.service
check_command "Removing shardeum-telegram-bot.service"

# Reload systemd to apply changes
echo "Reloading systemd..."
systemctl daemon-reload
check_command "Reloading systemd"

# Remove the scripts
echo "Removing scripts..."
rm -f /usr/local/bin/shardeum_validator.sh
check_command "Removing shardeum_validator.sh"
rm -f /usr/local/bin/shardeum_telegram_bot.sh
check_command "Removing shardeum_telegram_bot.sh"

# Remove log file
echo "Removing log file..."
rm -f /root/shardeum_validator.log
check_command "Removing shardeum_validator.log"

echo "All services and files have been successfully removed."
