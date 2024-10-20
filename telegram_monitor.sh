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
        # Capture the full status output with retries
        local RETRY_COUNT=0
        local MAX_RETRIES=5
        local STATUS_OUTPUT=""
        
        while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
            STATUS_OUTPUT=\$(docker exec shardeum-dashboard operator-cli status 2>&1)

            # Check if the output contains 'state:'
            if echo "\$STATUS_OUTPUT" | grep -q 'state:'; then
                break
            fi

            echo "Attempt \$((\$RETRY_COUNT + 1)): Unable to retrieve status, retrying..."
            ((RETRY_COUNT++))
            sleep 2  # Wait before retrying
        done

        # If we still can't get the status, log an error and exit
        if [ \$RETRY_COUNT -eq \$MAX_RETRIES ]; then
            TIMESTAMP=\$(TZ=\$TIMEZONE date '+%Y-%m-%d %H:%M UTC+2')
            echo "[\${TIMESTAMP}] Error: Unable to retrieve node status after \$MAX_RETRIES attempts" >> \$LOG_FILE
            return
        fi

        # Get only the state line and extract the status
        STATUS=\$(echo "\$STATUS_OUTPUT" | grep -oP 'state: \K(active|standby|stopped|offline|waiting-for-network)' | tail -n 1)

        # Get the current timestamp in UTC+2 (Kyiv)
        TIMESTAMP=\$(TZ=\$TIMEZONE date '+%Y-%m-%d %H:%M UTC+2')

        # Log the status or error message
        if [ -z "\$STATUS" ]; then
            STATUS="unknown"
            echo "[\${TIMESTAMP}] Error: Unable to determine node status from output: \$STATUS_OUTPUT" >> \$LOG_FILE
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
        docker start shardeum-dashboard
            if [ "\$(docker ps -q -f name=shardeum-dashboard)" ]; then
                echo "[\${TIMESTAMP}] Event: shardeum-dashboard container started successfully" >> \$LOG_FILE
            else
                echo "[\${TIMESTAMP}] Error: Failed to start shardeum-dashboard container" >> \$LOG_FILE
            fi
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
IP=\$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')

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
    local RETRY_COUNT=0
    local MAX_RETRIES=5
    local STATUS_OUTPUT=""
    
    # Try to get the status with retries
    while [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
        STATUS_OUTPUT=\$(docker exec shardeum-dashboard operator-cli status 2>/dev/null)
        
        # Check if the output contains 'state:'
        if echo "\$STATUS_OUTPUT" | grep -q 'state:'; then
            break
        fi

        echo "Attempt \$((\$RETRY_COUNT + 1)): Unable to retrieve status, retrying..."
        ((RETRY_COUNT++))
        sleep 2  # Wait before retrying
    done

    # If unable to retrieve status after all retries, log an error and exit
    if [ \$RETRY_COUNT -eq \$MAX_RETRIES ]; then
        echo "Error: Unable to retrieve node status after \$MAX_RETRIES attempts"
        STATUS="unknown"
    else
        # Extract the node status
        STATUS=\$(echo "\$STATUS_OUTPUT" | grep -oP 'state: \K(active|standby|stopped|offline|waiting-for-network)' | tail -n 1)
    fi

    HOSTNAME=\$(hostname)
    if [ "\$INCLUDE_IP" == "true" ]; then
        SERVER_IP="\$IP"
    else
        SERVER_IP=""
    fi

    # Define emoji based on node status
    if [ "\$STATUS" == "stopped" ]; then
        STATUS_EMOJI="❌ stopped"
    elif [ "\$STATUS" == "waiting-for-network" ]; then
        STATUS_EMOJI="⏳ waiting-for-network"
    elif [ "\$STATUS" == "standby" ]; then
        STATUS_EMOJI="🟢 standby"
    elif [ "\$STATUS" == "active" ]; then
        STATUS_EMOJI="🔵 active"
    else
        STATUS_EMOJI="unknown"
    fi

    # Send Telegram notification if status has changed
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
