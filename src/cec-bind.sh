#!/usr/bin/env bash

# display script help
show_help() {
	echo "Simple cec-client <https://github.com/Pulse-Eight/libcec> wrapper."
	echo ""
	echo "This script starts CEC client in the background. Every remote control key event"
	echo "(pressed, released, auto-released) can be 'converted' into keyboard event (as"
	echo "set in config file)."
	echo ""
	echo "For more info see:"
	echo "    https://github.com/fffilo/cec-bind.git"
	echo ""
	echo "Dependencies:"
	echo "    cec-client            https://github.com/Pulse-Eight/libcec"
	echo "    xautomation           https://linux.die.net/man/7/xautomation"
	echo "    perl                  http://perldoc.perl.org/perl.html"
	echo ""
	echo "Usage:"
	echo "    cec-bind [OPTIONS]"
	echo ""
	echo "Options:"
	echo "    -h|--help             show this help"
	echo "    --config=[VALUE]      path of keymap config file"
	echo "    --osd-name=[VALUE]    set CEC client OSD name"
	echo "    --display=[VALUE]     remote X server"
}

# does command exists
command_exists() {
	type "$1" &> /dev/null
}

# get cec-clinet tx codes for setting osd name
osd_name() {
	if [ -n "$1" ]; then
			param="$1"
	else
			param="cec-bind"
	fi

	echo "tx 10:47:`printf "$param" | xxd -pu | fold -w2 | paste -sd ":" -`"
}

# cec-clinet
client() {
	cec-client
}

# filter cec-client key events
filter() {
	perl -nle 'BEGIN{$|=1} /key (.*): (.*?) \(/ && print "$1|$2"'
}

# parse cec-client key events
parse() {
	while read line; do
		timestamp=`date +"%Y-%m-%d %H:%M:%S"`
		action=`cut -d\| -f1 <<< "$line"`
		key=`cut -d\| -f2 <<< "$line"`
		cmd=`create_command $action $key`
		status="OK"

		#eval $cmd >/dev/null 2>&1
		#status=$?
		#if [ $status -eq 0 ]; then
		#	status="OK"
		#else
		#	status="Non zero status code: ${status}"
		#fi

		# execute command and capture t_std/t_err
		eval "$( (eval $cmd) 2> >(t_err=$(cat); typeset -p t_err) > >(t_std=$(cat); typeset -p t_std) )"
		if [ -n "$t_std" ]; then
			status="${t_std##*$'\n'}"
		fi
		if [ -n "$t_err" ]; then
			status="${t_err##*$'\n'}"
		fi

		# log
		echo ""
		echo "TIMESTAMP: $timestamp"
		echo "ACTION:    $action"
		echo "KEY:       $key"
		echo "COMMAND:   $cmd"
		echo "STATUS:    $status"
	done
}

# create xte command by given action/key
create_command() {
	action="$1"
	key="$2"
	map=""

	# get keymap from config
	if [[ -f $C ]]; then
		map=`grep "^${action} ${key} " ${C} | tail -n 1`
	fi

	# split
	action=`cut -d " " -f1 <<< "$map"`
	key=`cut -d " " -f2 <<< "$map"`
	codes=`cut -d " " -f3- <<< "$map"`
	result="xte"

	# codes to array (preserve spaces in quoted arguments)
	IFS=$'\n'; array=($(echo $codes | egrep -o '"[^"]*"|\S+'))

	# keydown
	for key in "${!array[@]}"; do
		if [ $((key+1)) -lt ${#array[@]} ]; then
			result="${result} 'keydown ${array[$key]}'"
		fi
	done

	# keypress
	# to do: use 'str' instead 'key' if code is in quotes
	result="${result} 'key ${array[@]: -1}'"

	# keyup
	for key in `printf '%s\n' "${!array[@]}"|tac`; do
		if [ $((key+1)) -lt ${#array[@]} ]; then
			result="${result} 'keyup ${array[$key]}'"
		fi
	done

	echo $result
}

# defaults
export X=$DISPLAY
export N="cec-bind"
export C="${HOME}/.cec-bind"

# arguments
while test $# -gt 0; do
	case "$1" in
		-h|--help)
			show_help
			exit 0;;
		--config=*)
			export C=`echo $1 | sed -e 's/^[^=]*=//g'`
			shift;;
		--osd-name=*)
			export N=`echo $1 | sed -e 's/^[^=]*=//g'`
			shift;;
		--display=*)
			export X=`echo $1 | sed -e 's/^[^=]*=//g'`
			shift;;
		*)
			show_help
			echo ""
			echo "Invalid argument: $1"
			exit 1;;
	esac
done

if ! command_exists "cec-client"; then
	echo "Command \`cec-client\` not found."
	echo "See \`https://github.com/Pulse-Eight/libcec\`."
	exit 1
fi
if ! command_exists "perl"; then
	# to do: replace perl with sed?
	echo "Command \`perl\` not found."
	echo "Try executing \`sudo apt-get install perl\`."
	exit 1
fi
if ! command_exists "xte"; then
	echo "Command \`xte\` not found."
	echo "Try executing \`sudo apt-get install xautomation\`."
	exit 1
fi

# display info
cec-client --info

# warning
if [[ -f $C ]]; then
	echo "Warning: config file not found \`${C}\`."
fi
if ! [ -n "$1" ]; then
	echo "Warning: display variable not set."
fi

#echo "as" | client | filter | parse
echo `osd_name "$N"` | client | filter | parse
