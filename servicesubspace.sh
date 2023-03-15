






sudo tee <<EOF >/dev/null /etc/systemd/system/subspace.service
[Unit]
Description=subspace Node
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root/
ExecStart=/root/subspace-cli-ubuntu-x86_64-v0.1.9-alpha farm        
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF