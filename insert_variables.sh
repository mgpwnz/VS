. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_log -v "sudo journalctl -fn 100 -u massad" -a
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_client -v ". <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/cli_client.sh) -l UA -a client" -a
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_cli_client -v ". <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/cli_client.sh) -l UA" -a
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_node_info -v ". <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/cli_client.sh) -l UA -a node_info 2>/dev/null" -a
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_wallet_info -v ". <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/cli_client.sh) -l UA -a wallet_info" -a
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/insert_variable.sh) -n massa_buy_rolls -v ". <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/cli_client.sh) -l UA -a buy_rolls" -a