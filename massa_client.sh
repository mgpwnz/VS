#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -ml|--massa_log)
            function="massa_log"
            shift
            ;;
        -dis|--discord)
            function="discord"
            shift
            ;;
        -rs|--staking)   
            function="staking"
            shift
            ;;
        -wi|--wallet_info)
            function="wallet_info"
            shift
            ;;
        *|--)
		break
		;;
	esac
done
#Functions
discord(){
    local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local discord_id
    printf "discord_id"
    read -r discord_id
    local resp=`./massa-client -p "$massa_password" -j node_testnet_rewards_program_ownership_proof "$main_address" "$discord_id" | jq -r`
    echo "Insert do discord" "$resp"
}
staking(){
    local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local resp=`./massa-client -p "$massa_password" node_start_staking "$address"`
	if grep -q "error" <<< "$resp"; then
		echo Cant reg staking
	else
		echo Done
	fi
}
wallet_info(){
    local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local staking_addresses=`./massa-client -p "$massa_password" -j node_get_staking_addresses`
	local wallets=`jq -r "to_entries[]" <<< "$wallet_info" | tr -d '[:space:]' | sed 's%}{%} {%g'`
		printf 
		for wallet in $wallets; do
			local address=`jq -r ".key" <<< "$wallet"`
			printf "Wallet address" "$address"
			local public_key=`jq -r ".value.keypair.public_key" <<< "$wallet"`
			printf "Public key:      " "$public_key"
			if grep -q "$address" <<< "$staking_addresses"; then
				printf "Registered for staking:     yes"
			else
				printf "Registered for staking:     no"
			fi
			local balance=`jq -r ".value.address_info.candidate_balance" <<< "$wallet"`
			printf  "Balance         " "$balance"
			local total_rolls=`jq -r ".value.address_info.candidate_rolls" <<< "$wallet"`
			print  "Total ROLLs:     " "$total_rolls"
			local active_rolls=`jq -r ".value.address_info.active_rolls" <<< "$wallet"`
			printf  "Active ROLLs:    " "$active_rolls"
			printf 
		done
}

#Actions
sudo apt install jq bc -y &>/dev/null
cd $HOME/massa/massa-client/
if grep -q "wrong password" <<< `./massa-client -p "$massa_password" 2>&1`; then
	echo Bad passwd
	return 1 2>/dev/null; exit 1
fi
cd