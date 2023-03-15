#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
		break
		;;
	esac
done
install() {
cd 
if [ ! -d $HOME/subspace ]; then
mkdir $HOME/subspace
fi
cd $HOME/subspace
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/v0.1.9-alpha/subspace-cli-ubuntu-x86_64-v0.1.9-alpha && \
chmod +x subspace-cli-ubuntu-x86_64-v0.1.9-alpha && \
./subspace-cli-ubuntu-x86_64-v0.1.9-alpha init
sleep 2
#service
sudo tee <<EOF >/dev/null /etc/systemd/system/subspace.service
[Unit]
Description=subspace Node
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root/subspace/
ExecStart=/root/subspace/subspace-cli-ubuntu-x86_64-v0.1.9-alpha farm        
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF
sleep 1 
cd $HOME
systemctl restart systemd-journald 
systemctl daemon-reload 
systemctl enable subspace
systemctl restart subspace
echo -e '\n\e[42mCheck node status\e[0m\n' && sleep 1
if [[ `service subspace status | grep active` =~ "running" ]]; then
  echo -e "Your subspace node \e[32minstalled and works\e[39m!"
  echo -e "You can check node status by the command \e[7mservice subspace status\e[0m"
  echo -e "Press \e[7mQ\e[0m for exit from status menu"
else
 echo -e "Your subspace node \e[31mwas not installed correctly\e[39m, please reinstall."
fi
}
uninstall() {
sudo systemctl disable subspace
sudo systemctl stop subspace    
sudo rm -rf $HOME/subspace 
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}

# Actions
sudo apt install tmux wget -y &>/dev/null
cd
$function