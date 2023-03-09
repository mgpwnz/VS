#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -dp|--deploy)
            function="deploy"
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
# change config
install() {
    #upd&upg
    sudo apt update
	sudo apt upgrade -y    
    #install rust
    sudo curl https://sh.rustup.rs -sSf | sh -s -- -y
	. $HOME/.cargo/env
    #install Leo
    git clone https://github.com/AleoHQ/leo
    cd leo
    cargo install --path .
    #install Shark OS
    git clone https://github.com/AleoHQ/snarkOS.git --depth 1
    cd snarkOS
    cargo install --path .
    #Create a Leo application
    cd $HOME/
    mkdir demo_deploy_Leo_app && cd demo_deploy_Leo_app
    #Wallet
    if [ ! $WALLETADDRESS ]; then
		read -p "Enter wallet address: " WALLETADDRESS
		echo 'export WALLETADDRESS='${WALLETADDRESS} >> $HOME/.bash_profile
	fi
    echo -e '\n\e[42mYour wallet address:' $WALLETADDRESS '\e[0m\n'
    #Wallet Name
    if [ ! $WALLETADDRESS ]; then
		read -p "Enter wallet name: " NAME
		echo 'export NAME='${NAME} >> $HOME/.bash_profile
	fi
    echo -e '\n\e[42mYour wallet name:' $NAME '\e[0m\n'
    #Appname
    APPNAME=${NAME}_"${WALLETADDRESS:4:6}"
    #Create a new test Leo application  
    leo new "${APPNAME}"
    #Run your Leo application to make sure things are working
    cd "${APPNAME}" && leo run && cd -
    #Save the path of your application — this is important later
    PATHTOAPP=$(realpath -q $APPNAME)
    echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
	. $HOME/.bash_profile
    sleep 1
}
deploy(){
#Navigate to the path of your app
cd $PATHTOAPP && cd ..
#PRIVATEKEY
    if [ ! $PRIVATEKEY ]; then
		read -p "Enter wallet address: " PRIVATEKEY
		echo 'export PRIVATEKEY='${PRIVATEKEY} >> $HOME/.bash_profile
	fi
    PRIVATEKEY="${PRIVATEKEY}"
#Record
    if [ ! $PRIVATEKEY ]; then
		read -p "Enter wallet address: " RECORD
		echo 'export RECORD='${RECORD} >> $HOME/.bash_profile
	fi
    RECORD="${RECORD}"
#Deploy your Leo application (if all your variables were assigned correctly, you should be able to copy/paste the following
snarkos developer deploy "${APPNAME}.aleo" --private-key "${PRIVATEKEY}" --query "https://vm.aleo.org/api" --path "./${APPNAME}/build/" --broadcast "https://vm.aleo.org/api/testnet3/transaction/broadcast" --fee 600000 --record "${RECORD}"
}

uninstall() {
cd /root
sudo rm -rf $HOME/Leo $HOME/sharkOS
sudo rm -rf $HOME/demo_deploy_Leo_app
echo "Done"
}
# Actions
sudo apt install  wget -y &>/dev/null
cd
$function