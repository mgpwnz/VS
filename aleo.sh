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
    cd $HOME/
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
    . $HOME/.bash_profile
    #Appname
    APPNAME=helloworld_"${WALLETADDRESS:4:6}"
    echo 'export APPNAME='${APPNAME} >> $HOME/.bash_profile
    . $HOME/.bash_profile
    #Create a new test Leo application  
    leo new "${APPNAME}"
    #Run your Leo application to make sure things are working
    cd "${APPNAME}" && leo run && cd -
    #Save the path of your application — this is important later
    PATHTOAPP=$(realpath -q $APPNAME)
    echo 'export PATHTOAPP='${PATHTOAPP} >> $HOME/.bash_profile
    echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
	. $HOME/.bash_profile
    sleep 1
    cd
}
deploy(){
#Navigate to the path of your app
cd $PATHTOAPP && cd ..
#PRIVATEKEY
    if [ ! $PRIVATEKEY ]; then
		read -p "Enter Private Key: " PRIVATEKEY
		echo 'export PRIVATEKEY='${PRIVATEKEY} >> $HOME/.bash_profile
	fi
    PRIVATEKEY="${PRIVATEKEY}"
    . $HOME/.bash_profile
    sleep 1
#Record
    if [ ! $RECORD ]; then
		read -p "Enter wallet address: " RECORD
		echo 'export RECORD='${RECORD} >> $HOME/.bash_profile
	fi
    RECORD="${RECORD}"
    . $HOME/.bash_profile
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