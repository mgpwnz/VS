#!/bin/bash
# Default variables
function="install"
version=v0.1.9-alpha
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
sudo apt-get install wget jq ocl-icd-opencl-dev libopencl-clang-dev libgomp1 ocl-icd-libopencl1 -y
sleep 2
if [ ! -d $HOME/subspace ]; then
mkdir $HOME/subspace
fi
cd $HOME/subspace
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${version}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#service
cd $HOME
echo "[Unit]
Description=Subspace Node
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=/root/subspace/
ExecStart=/root/subspace/subspace-cli-ubuntu-x86_64-${version} farm  --verbose
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
" > $HOME/subspace.service
sudo mv $HOME/subspace.service /etc/systemd/system
sudo systemctl restart systemd-journald 
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e '\n\e[42mCheck node status\e[0m\n' && sleep 1
if [[ `service subspace status | grep active` =~ "running" ]]; then
  echo -e "Your subspace node \e[32minstalled and works\e[39m!"
  echo -e "You can check node status by the command \e[7mservice subspace status\e[0m"
  echo -e "Use \e[7mjournalctl -fu subspace\e[0m for logs"
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
sudo apt install wget -y &>/dev/null
cd
$function