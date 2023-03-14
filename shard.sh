#!/bin/bash
# Default variables
function="autorun"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -ar|--autorun)
            function="autorun"
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
autorub() {
cd /root
sleep 1
 # Create script 





echo "Done"
}
uninstall() {
cd /root
sudo rm $HOME/autorun.sh 
echo "Done"
}
# Actions
sudo apt install tmux wget -y &>/dev/null
cd
$function