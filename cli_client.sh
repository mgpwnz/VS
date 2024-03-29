#!/bin/bash
# Default variables
insert_variables="false"
action=""
language="EN"
raw_output="false"
secret_keys="false"
max_buy="false"

# Options
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/colors.sh) --
option_value(){ echo $1 | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
	case "$1" in
	-a*|--action*)
		if ! grep -q "=" <<< $1; then shift; fi
		action=`option_value $1`
		shift
		;;
	-l*|--language*)
		if ! grep -q "=" <<< $1; then shift; fi
		language=`option_value $1`
		shift
		;;
	-sk|--secret-keys)
		secret_keys="true"
		shift
		;;
	-mb|--max-buy)
		max_buy="true"
		shift
		;;
	-ro|--raw-output)
		raw_output="true"
		shift
		;;
	*|--)
		break
		;;
	esac
done

# Texts

if [ "$language" = "UA" ]; then
	t_ni1="\nID ноди:              ${C_Y}%s${RES}"
	t_ni2="Версія ноди:          ${C_Y}%s${RES}\n"
	
	t_ni3="Поточний цикл:        ${C_Y}%d${RES}"
	
	t_ni6="Порти відкриті:       ${C_Y}так${RES}"
	t_ni7="Порти відкриті:       ${C_R}ні${RES}"
	t_ni8="Вхідних підключень:   ${C_Y}%d${RES}"
	t_ni9="Вихідних підключень:  ${C_Y}%d${RES}\n\n"
	t_ni10="   Гаманці"
	
	
	t_wi1="Адреса гаманця:    ${C_Y}%s${RES}"
	t_wi2=" (${C_Y}основний${RES})"
	t_wi3="Приватний ключ:    ${C_Y}%s${RES} (${C_R}нікому не показувати${RES})"
	t_wi4="Публічний ключ:    ${C_Y}%s${RES}"
	t_wi5="Зареєстрований\nдля стейкінгу:     ${C_Y}так${RES}"
	t_wi6="Зареєстрований\nдля стейкінгу:     ${C_R}ні${RES}"
	t_wi7="Баланс:            ${C_Y}%f${RES}"
	t_wi8="Загалом ROLL'ів:   ${C_Y}%d${RES}"
	t_wi9="Активних ROLL'ів:  ${C_Y}%d${RES}"
	
	
	t_br1="${C_R}Баланс менш ніж 100 токенів${RES}"
	t_br2="Куплено ROLL'ів: ${C_Y}%d${RES}"
	t_br3="Введіть кількість ROLL'ів (максимально ${C_Y}%d${RES}): "
	t_br4="${C_R}Недостатньо токенів для придбання${RES}"
	
	
	t_rpk="${C_R}Не вдалося зареєструвати ключ для стейкінгу${RES}"
	
	
	t_ctrp1="${C_Y}Введіть Discord ID:${RES} "
	t_ctrp2="\nНадішліть Discord боту наступне:\n${C_Y}%s${RES}\n"
	
	
	t_done="${C_Y}Готово!${RES}"
	t_err="${C_R}Немає такої дії!${RES}"
	t_err_mp1="\n${C_R}Не існує змінної massa_password з паролем, введіть його для збереження у змінній!${RES}"
	t_err_mp2="\n${C_R}Не існує змінної massa_password з паролем!${RES}\n"
	t_err_wp="\n${C_R}Невірний пароль!${RES}\n"
	t_err_nwn="\n${C_R}Нода не працює!${RES}\nПодивитися лог: ${C_Y}massa_log${RES}\n"
	
fi

# Functions
printf_n(){ printf "$1\n" "${@:2}"; }
client() { ./massa-client -p "$massa_password"; }
node_info() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local node_info=`./massa-client -p "$massa_password" -j get_status | jq`
	if [ "$raw_output" = "true" ]; then
		printf_n "$node_info"
	else
		local node_id=`jq -r ".node_id" <<< "$node_info"`
		printf_n "$t_ni1" "$node_id"
		local node_version=`jq -r ".version" <<< "$node_info"`
		printf_n "$t_ni2" "$node_version"
		
		local current_cycle=`jq -r ".current_cycle" <<< "$node_info"`
		printf_n "$t_ni3" "$current_cycle"
		
		printf_n
		local opened_ports=`ss -tulpn | grep :3303`
		if [ -n "$opened_ports" ]; then
			printf_n "$t_ni6"
		else
			printf_n "$t_ni7"
		fi
		local incoming_connections=`jq -r ".network_stats.in_connection_count" <<< "$node_info"`
		printf_n "$t_ni8" "$incoming_connections"
		local outcoming_connections=`jq -r ".network_stats.out_connection_count" <<< "$node_info"`
		printf_n "$t_ni9" "$outcoming_connections"
		printf_n "$t_ni10"
		wallet_info
	fi
}
wallet_info() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	if [ "$raw_output" = "true" ]; then
		printf_n "`jq -r "[.[]]" <<< "$wallet_info"`"
	else
		local staking_addresses=`./massa-client -p "$massa_password" -j node_get_staking_addresses`
		local wallets=`jq -r "to_entries[]" <<< "$wallet_info" | tr -d '[:space:]' | sed 's%}{%} {%g'`
		printf_n
		for wallet in $wallets; do
			local address=`jq -r ".key" <<< "$wallet"`
			printf "$t_wi1" "$address"
			if [ "$address" = "$main_address" ]; then
				printf_n "$t_wi2"
			else
				printf_n
			fi
			if [ "$secret_keys" = "true" ]; then
				local secret_key=`jq -r ".value.keypair.secret_key" <<< "$wallet"`
				printf_n "$t_wi3" "$secret_key"
			fi
			local public_key=`jq -r ".value.keypair.public_key" <<< "$wallet"`
			printf_n "$t_wi4" "$public_key"
			if grep -q "$address" <<< "$staking_addresses"; then
				printf_n "$t_wi5"
			else
				printf_n "$t_wi6"
			fi
			local balance=`jq -r ".value.address_info.candidate_balance" <<< "$wallet"`
			printf_n "$t_wi7" "$balance"
			local total_rolls=`jq -r ".value.address_info.candidate_rolls" <<< "$wallet"`
			printf_n "$t_wi8" "$total_rolls"
			local active_rolls=`jq -r ".value.address_info.active_rolls" <<< "$wallet"`
			printf_n "$t_wi9" "$active_rolls"
			printf_n
		done
	fi
}
buy_rolls() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local balance=`jq -r "[.[]] | .[-1].address_info.candidate_balance" <<< "$wallet_info"`
	local roll_count=`printf "%d" $(bc -l <<< "$balance/100") 2>/dev/null`
	if [ "$roll_count" -eq "0" ]; then
		printf_n "$t_br1"
	elif [ "$max_buy" = "true" ]; then
		local resp=`./massa-client -p "$massa_password" buy_rolls "$main_address" "$roll_count" 0`
		if grep -q 'insuffisant balance' <<< "$resp"; then
			printf_n "$t_br4"
			return 1 2>/dev/null; exit 1
		else
			printf_n "$t_br2" "$roll_count"
		fi
	else
		printf "$t_br3" "$roll_count"
		local rolls_for_buy
		read -r rolls_for_buy
		if [ "$rolls_for_buy" -gt "$roll_count" ]; then
			local resp=`./massa-client -p "$massa_password" buy_rolls "$main_address" "$roll_count" 0`
		else
			local resp=`./massa-client -p "$massa_password" buy_rolls "$main_address" "$rolls_for_buy" 0`
		fi
		if grep -q 'insuffisant balance' <<< "$resp"; then
			printf_n "$t_br4"
			return 1 2>/dev/null; exit 1
		else
			printf_n "$t_done"
		fi
	fi
}
node_start_staking() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local resp=`./massa-client -p "$massa_password" node_start_staking "$address"`
	if grep -q "error" <<< "$resp"; then
		printf_n "$t_rpk"
	else
		printf_n "$t_done"
	fi
}
node_testnet_rewards_program_ownership_proof() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local discord_id
	printf "$t_ctrp1"
	read -r discord_id
	local resp=`./massa-client -p "$massa_password" -j node_testnet_rewards_program_ownership_proof "$main_address" "$discord_id" | jq -r`
	printf_n "$t_ctrp2" "$resp"
}
other() {
	if [ "$raw_output" = "true" ]; then
		local resp=`./massa-client -p "$massa_password" -j "$action" "$@" 2>&1`
	else
		local resp=`./massa-client -p "$massa_password" "$action" "$@" 2>&1`
	fi
	if grep -q 'error: Found argument' <<< "$resp"; then
		printf_n "$t_err"
		return 1 2>/dev/null; exit 1
	else
		printf_n "$resp"
	fi
}

# Actions
sudo apt install jq bc -y &>/dev/null
if [ ! -n "$massa_password" ]; then
	printf_n "$t_err_mp1"
	. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_password
fi
if [ ! -n "$massa_password" ]; then
	printf_n "$t_err_mp2"
	return 1 2>/dev/null; exit 1
fi
cd $HOME/massa/massa-client/
if grep -q "wrong password" <<< `./massa-client -p "$massa_password" 2>&1`; then
	printf_n "$t_err_wp"
	return 1 2>/dev/null; exit 1
fi

if grep -q "check if your node is running" <<< `./massa-client -p "$massa_password" get_status`; then
	printf_n "$t_err_nwn"
else
	if grep -q "$action" <<< "client node_info wallet_info buy_rolls node_start_staking node_testnet_rewards_program_ownership_proof"; then $action; else other "$@"; fi
fi
cd