#!/bin/bash 

# Check if user is root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Configuration variables
LOG_FILE="/root/shardeum_validator.log"
SERVICE_FILE="/etc/systemd/system/shardeum-validator.service"
SCRIPT_FILE="/usr/local/bin/shardeum_validator.sh"
BOT_SCRIPT="/usr/local/bin/shardeum_telegram_bot.sh"

# Prompt for Telegram Bot configuration
read -p "Would you like to install Telegram Bot for status notifications? (Y/N): " install_telegram
if [[ $install_telegram =~ ^[Yy]$ ]]; then
    read -p "Enter your TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
    read -p "Enter your TELEGRAM_CHAT_ID: " TELEGRAM_CHAT_ID
    read -p "Include server IP in Telegram notifications? (Y/N): " include_ip
    if [[ $include_ip =~ ^[Yy]$ ]]; then
        INCLUDE_IP="true"
    else
        INCLUDE_IP="false"
    fi
else
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    INCLUDE_IP="false"
fi

# Create the Shardeum Validator Script
cat <<EOF > $SCRIPT_FILE
#!/bin/bash

LOG_FILE="$LOG_FILE"
TIMEZONE="Europe/Kyiv"

# Function to log status with timestamp in UTC+2 (Kyiv)
log_status() {
    # Check if the shardeum-dashboard container is running
    if [ "\$(docker ps -q -f name=shardeum-dashboard)" ]; then
        # Capture the full status output
        STATUS_OUTPUT=\$(docker exec shardeum-dashboard operator-cli status 2>&1)

        # Get only the state line and extract the status
        STATUS=\$(echo "\$STATUS_OUTPUT" | grep -i "state:" | awk '{print \$2}' | tr -d '[:space:]' | head -n 1)

        # Get the current timestamp in UTC+2 (Kyiv)
        TIMESTAMP=\$(TZ=\$TIMEZONE date '+%Y-%m-%d %H:%M UTC+2')

        # Log the status or error message
        if [ -z "\$STATUS" ]; then
            STATUS="unknown"
            echo "[\${TIMESTAMP}] Error: Unable to retrieve node status" >> \$LOG_FILE
        else
            echo "[\${TIMESTAMP}] Node Status: \$STATUS" >> \$LOG_FILE
        fi

        # If the node is offline or stopped, try to start it
        if [[ "\$STATUS" == "offline" || "\$STATUS" == "stopped" ]]; then
            echo "[\${TIMESTAMP}] Node is \$STATUS, attempting to start..." >> \$LOG_FILE
            docker exec shardeum-dashboard operator-cli start
        fi
    else
        TIMESTAMP=\$(TZ=\$TIMEZONE date '+%Y-%m-%d %H:%M UTC+2')
        echo "[\${TIMESTAMP}] Error: shardeum-dashboard container is not running" >> \$LOG_FILE
    fi
}

# Run log_status every 15 minutes
while true; do
    log_status
    sleep 900  # 15 minutes
done
EOF

# Make the script executable
chmod +x $SCRIPT_FILE

# Create Systemd Service
cat <<EOF > $SERVICE_FILE
[Unit]
Description=Shardeum Validator Manager
After=docker.service
Requires=docker.service

[Service]
ExecStart=$SCRIPT_FILE
Restart=always
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable shardeum-validator.service
systemctl start shardeum-validator.service

echo "Shardeum Validator systemd service installed and started."

# If Telegram bot is selected, install the Telegram bot script
if [[ $install_telegram =~ ^[Yy]$ ]]; then
cat <<EOF > $BOT_SCRIPT
#!/bin/bash

# Telegram Bot variables
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
INCLUDE_IP="$INCLUDE_IP"

PREV_STATUS=""

# Function to send Telegram notification
send_telegram_message() {
    local MESSAGE=\$1
    # Replace newline escape characters with actual newlines
    MESSAGE=\$(echo -e "\$MESSAGE")
    curl -s -X POST https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/sendMessage -d chat_id=\$TELEGRAM_CHAT_ID -d text="\$MESSAGE"
}

# Function to check status and send notification if changed
check_status() {
    STATUS=\$(docker exec shardeum-dashboard operator-cli status 2>/dev/null | grep -i "state:" | head -n 1 | awk '{print \$2}' | tr -d '[:space:]')

    HOSTNAME=\$(hostname)
    if [ "\$INCLUDE_IP" == "true" ]; then
        SERVER_IP=\$(hostname -I | awk '{print \$1}')
    else
        SERVER_IP=""
    fi

    # Use a case statement for better readability
    case "\$STATUS" in
        "stopped")
            STATUS_EMOJI="❌ stopped"
            ;;
        "waiting-for-network")
            STATUS_EMOJI="⏳ waiting-for-network"
            ;;
        "standby")
            STATUS_EMOJI="🟢 standby"
            ;;
        "active")
            STATUS_EMOJI="🔵 active"
            ;;
        *)
            STATUS_EMOJI="unknown"
            ;;
    esac

    # Check if status changed and send Telegram notification
    if [ "\$STATUS" != "\$PREV_STATUS" ]; then
        MESSAGE="Host: \$HOSTNAME"
        if [ -n "\$SERVER_IP" ]; then
            MESSAGE="\$MESSAGE\nIP: \$SERVER_IP"
        fi
        MESSAGE="\$MESSAGE\nStatus: \$STATUS_EMOJI"
        send_telegram_message "\$MESSAGE"
        
        PREV_STATUS="\$STATUS"
    fi
}

# Run check_status every 5 minutes
while true; do
    check_status
    sleep 300  # 5 minutes
done
EOF

# Make the Telegram bot script executable
chmod +x $BOT_SCRIPT

# Create Telegram Bot Systemd Service
cat <<EOF > /etc/systemd/system/shardeum-telegram-bot.service
[Unit]
Description=Shardeum Telegram Bot
After=docker.service
Requires=docker.service

[Service]
ExecStart=$BOT_SCRIPT
Restart=always
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable Telegram bot service
systemctl daemon-reload
systemctl enable shardeum-telegram-bot.service
systemctl start shardeum-telegram-bot.service

echo "Shardeum Telegram bot installed and started."
fi

echo "Installation complete."
