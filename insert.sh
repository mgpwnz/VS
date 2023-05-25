#!/bin/bash
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
	case "$1" in
	-nss*|--node_start_staking)
	    function="node_start_staking"
		shift
		;;
	-wi*|--wallet_info)
		function=wallet_info
		shift
		;;
	-ntrp|--node_testnet_rewards_program_ownership_proof)
		type="node_testnet_rewards_program_ownership_proof"
		shift
     ;;
        *|--)
		break
		;;
	esac
done
printf_n(){ printf "$1\n" "${@:2}"; }
node_start_staking() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local resp=`./massa-client -p "$massa_password" node_start_staking "$address"`
	if grep -q "error" <<< "$resp"; then
		echo Не удалось зарегистрировать ключ для стейкинга
	else
		echo Готово
	fi
}
wallet_info() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local staking_addresses=`./massa-client -p "$massa_password" -j node_get_staking_addresses`
	local wallets=`jq -r "to_entries[]" <<< "$wallet_info" | tr -d '[:space:]' | sed 's%}{%} {%g'`
		printf_n
		for wallet in $wallets; do
			local address=`jq -r ".key" <<< "$wallet"`
			printf  "$address"
			if [ "$address" = "$main_address" ]; then
				echo the main
			else
				printf_n
			fi
			if [ "$secret_keys" = "true" ]; then
				local secret_key=`jq -r ".value.keypair.secret_key" <<< "$wallet"`
				printf_n "Secret key:" "$secret_key"
			fi
			local public_key=`jq -r ".value.keypair.public_key" <<< "$wallet"`
			printf_n "Public key:" "$public_key"
			if grep -q "$address" <<< "$staking_addresses"; then
				printf_n "Registered\nfor staking:      yes"
			else
				printf_n "Registered\nfor staking:      no"
			fi
			local balance=`jq -r ".value.address_info.candidate_balance" <<< "$wallet"`
			printf_n "Balance:" "$balance"
			local total_rolls=`jq -r ".value.address_info.candidate_rolls" <<< "$wallet"`
			printf_n "Total ROLLs:" "$total_rolls"
			local active_rolls=`jq -r ".value.address_info.active_rolls" <<< "$wallet"`
			printf_n "Active ROLLs:" "$active_rolls"
			printf_n
		done
	fi
}
node_testnet_rewards_program_ownership_proof() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local discord_id
	echo Введите дискорд id
	read -r discord_id
	local resp=`./massa-client -p "$massa_password" -j node_testnet_rewards_program_ownership_proof "$main_address" "$discord_id" | jq -r`
	echo Discord боту наступне: "$resp"
}
cd