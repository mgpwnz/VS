#!/bin/bash
# Default variables
function="install"
repo=v0.1.11-alpha
version=v3-v0.1.11-alpha
installed=$(ls $HOME/subspace | sed -e "s%subspace-cli-ubuntu-x86_64-v%v%")
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
	 -in2|--install2)
            function="install2"
            shift
            ;;
	  -in3|--install3)
            function="install3"
            shift
            ;;
	  -in4|--install4)
            function="install4"
            shift
            ;;
	  -in5|--install5)
            function="install5"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
	-un2|--uninstall2)
            function="uninstall2"
            shift
            ;;
	-un3|--uninstall3)
            function="uninstall3"
            shift
            ;;
	-un4|--uninstall4)
            function="uninstall4"
            shift
            ;;
	-un5|--uninstall5)
            function="uninstall5"
            shift
            ;;
	 -up|--update)
            function="update"
            shift
            ;;
	 -up2|--update2)
            function="update2"
            shift
            ;;
	 -up3|--update3)
            function="update3"
            shift
            ;;
	 -up4|--update4)
            function="update4"
            shift
            ;;
	  -up5|--update5)
            function="update5"
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
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#Change ports
sed -i -e "s/9933/19999/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/9944/19998/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30333/19997/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30433/19996/g" $HOME/.config/subspace-cli/settings.toml
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
sudo rm -rf $HOME/subspace $HOME/.config/subspace*
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}
update() {
if [[ ${version} != ${installed} ]]; then
cd $HOME/subspace
rm subspace-cli-ubuntu*
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
sed -i -e "s/subspace-cli-ubuntu-x86_64-.*/subspace-cli-ubuntu-x86_64-${version} farm  --verbose/g" /etc/systemd/system/subspace.service
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e "Your subspace node \e[32mUpdate\e[39m!"
cd $HOME
else
echo -e "Your subspace node \e[32mlast version\e[39m!"
fi
}
install2() {
cd 
sudo apt-get install wget jq ocl-icd-opencl-dev libopencl-clang-dev libgomp1 ocl-icd-libopencl1 -y
sleep 2
if [ ! -d $HOME/subspace2 ]; then
mkdir $HOME/subspace2
fi
cd $HOME/subspace2
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#Change ports
sed -i -e "s/9933/19929/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/9944/19928/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30333/19927/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30433/19926/g" $HOME/.config/subspace-cli/settings.toml
#service
cd $HOME
echo "[Unit]
Description=Subspace Node2
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=/root/subspace2/
ExecStart=/root/subspace2/subspace-cli-ubuntu-x86_64-${version} farm  --verbose
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
" > $HOME/subspace2.service
sudo mv $HOME/subspace2.service /etc/systemd/system
sudo systemctl restart systemd-journald 
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace2
sudo systemctl restart subspace2
echo -e '\n\e[42mCheck node status\e[0m\n' && sleep 1
if [[ `service subspace2 status | grep active` =~ "running" ]]; then
  echo -e "Your subspace2 node \e[32minstalled and works\e[39m!"
  echo -e "You can check node status by the command \e[7mservice subspace status\e[0m"
  echo -e "Use \e[7mjournalctl -fu subspace2\e[0m for logs"
else
 echo -e "Your subspace2 node \e[31mwas not installed correctly\e[39m, please reinstall."
fi
}
uninstall() {
sudo systemctl disable subspace2
sudo systemctl stop subspace2    
sudo rm -rf $HOME/subspace $HOME/.config/subspace*
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}
update() {
if [[ ${version} != ${installed} ]]; then
cd $HOME/subspace
rm subspace-cli-ubuntu*
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
sed -i -e "s/subspace-cli-ubuntu-x86_64-.*/subspace-cli-ubuntu-x86_64-${version} farm  --verbose/g" /etc/systemd/system/subspace.service
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e "Your subspace node \e[32mUpdate\e[39m!"
cd $HOME
else
echo -e "Your subspace node \e[32mlast version\e[39m!"
fi
}
install() {
cd 
sudo apt-get install wget jq ocl-icd-opencl-dev libopencl-clang-dev libgomp1 ocl-icd-libopencl1 -y
sleep 2
if [ ! -d $HOME/subspace ]; then
mkdir $HOME/subspace
fi
cd $HOME/subspace
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#Change ports
sed -i -e "s/9933/19999/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/9944/19998/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30333/19997/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30433/19996/g" $HOME/.config/subspace-cli/settings.toml
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
sudo rm -rf $HOME/subspace $HOME/.config/subspace*
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}
update() {
if [[ ${version} != ${installed} ]]; then
cd $HOME/subspace
rm subspace-cli-ubuntu*
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
sed -i -e "s/subspace-cli-ubuntu-x86_64-.*/subspace-cli-ubuntu-x86_64-${version} farm  --verbose/g" /etc/systemd/system/subspace.service
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e "Your subspace node \e[32mUpdate\e[39m!"
cd $HOME
else
echo -e "Your subspace node \e[32mlast version\e[39m!"
fi
}
install() {
cd 
sudo apt-get install wget jq ocl-icd-opencl-dev libopencl-clang-dev libgomp1 ocl-icd-libopencl1 -y
sleep 2
if [ ! -d $HOME/subspace ]; then
mkdir $HOME/subspace
fi
cd $HOME/subspace
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#Change ports
sed -i -e "s/9933/19999/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/9944/19998/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30333/19997/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30433/19996/g" $HOME/.config/subspace-cli/settings.toml
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
sudo rm -rf $HOME/subspace $HOME/.config/subspace*
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}
update() {
if [[ ${version} != ${installed} ]]; then
cd $HOME/subspace
rm subspace-cli-ubuntu*
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
sed -i -e "s/subspace-cli-ubuntu-x86_64-.*/subspace-cli-ubuntu-x86_64-${version} farm  --verbose/g" /etc/systemd/system/subspace.service
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e "Your subspace node \e[32mUpdate\e[39m!"
cd $HOME
else
echo -e "Your subspace node \e[32mlast version\e[39m!"
fi
}
install() {
cd 
sudo apt-get install wget jq ocl-icd-opencl-dev libopencl-clang-dev libgomp1 ocl-icd-libopencl1 -y
sleep 2
if [ ! -d $HOME/subspace ]; then
mkdir $HOME/subspace
fi
cd $HOME/subspace
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
./subspace-cli-ubuntu-x86_64-${version} init
sleep 2
#Change ports
sed -i -e "s/9933/19999/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/9944/19998/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30333/19997/g" $HOME/.config/subspace-cli/settings.toml && \
sed -i -e "s/30433/19996/g" $HOME/.config/subspace-cli/settings.toml
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
sudo rm -rf $HOME/subspace $HOME/.config/subspace*
sudo rm -rf $HOME/.local/share/subspace-cli/
echo "Done"
cd
}
update() {
if [[ ${version} != ${installed} ]]; then
cd $HOME/subspace
rm subspace-cli-ubuntu*
#download cli
wget https://github.com/subspace/subspace-cli/releases/download/${repo}/subspace-cli-ubuntu-x86_64-${version} && \
chmod +x subspace-cli-ubuntu-x86_64-${version} && \
sed -i -e "s/subspace-cli-ubuntu-x86_64-.*/subspace-cli-ubuntu-x86_64-${version} farm  --verbose/g" /etc/systemd/system/subspace.service
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1 
sudo systemctl enable subspace
sudo systemctl restart subspace
echo -e "Your subspace node \e[32mUpdate\e[39m!"
cd $HOME
else
echo -e "Your subspace node \e[32mlast version\e[39m!"
fi
}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function
