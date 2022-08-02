#! /bin/bash
# shellcheck disable=SC2312,SC2310,SC2250

set -ue


# shellcheck disable=SC2155
declare -r date="$(date +%F_%T)"

function usage () {
	cat <<EOF
Usage:
	$0 [-no-color] [-debug] COMMAND [ARG ...]
Commands:
	mk [-o OWNER_USERNAME ] [-g GROUP] [-m MODE] FILE ...
	rm FILE ...
	not [-o OWNER_USERNAME ] [-g GROUP] [-m MODE] FILE ...
	edit FILE
	encrypt [-o OWNER] [-g GROUP] [-m MODE] [-k KEY] [-u KEY_OWNER] [-i -|+] FILE ...
	decrypt [-o OWNER] [-g GROUP] [-m MODE] [-k KEY] [-u KEY_OWNER] FILE ...
Note: When FILE begins with a dash (-),
you must prefix it with './' else it will be interpreted as an option.
EOF
	exit 1
}

no_color='' debug=''
while [[ $# -ne 0 ]]; do
	case "$1" in
		-no-color ) no_color=1 ;;
		-debug ) debug=1 ;;
		-* ) usage ;;
		* ) break ;;
	esac
	shift
done

if [[ -z "$no_color" ]]; then
	declare -r reset='\e[0m' ansicode_error='\e[1;37;41m' ansicode_info='\e[1;37;44m' ansicode_success='\e[1;30;42m' ansicode_debug='\e[2m'
else
	declare -r reset='' ansicode_error='' ansicode_info='' ansicode_success='' ansicode_debug=''
fi

[[ $# -ne 0 ]] || usage

function msg () {
	local args="$1" echo_args
	shift
	local echo="$*" log="$*" cmd_out='' exit_status
	declare -a echo_args=()
	if [[ "$args" = *n* ]]; then
		echo_args[${#echo_args[@]}]='-n'
	fi
	if [[ "$args" != *r* ]]; then
		echo_args[${#echo_args[@]}]='-e'
	fi
	case "$args" in
		*e* ) echo="$ansicode_error$*$reset" ;;
		*i* ) echo="${ansicode_info}$*${reset}" ;;
		*s* ) echo="${ansicode_success}$*${reset}" ;;
		*d* )
			cmd_out="$(mktemp)"
			if [[ -n "$debug" ]]; then
				echo -en "${ansicode_debug}running command: "
				echo -n "$*"
				echo -e "${reset}"
			fi
			eval "$*" |& tee "$cmd_out"
			exit_status="${PIPESTATUS[0]}"
			if [[ "$args" = *q* ]]; then
				log="running command: $*"
			else
				log="running command: $*
EXIT STATUS: $exit_status
BEGIN command output
$(cat "$cmd_out")
END command output"
			fi
			rm "$cmd_out"
			echo "$log" >> "$logs"
			return "$exit_status"
			;;
		* ) echo="$*" ;;
	esac
	#if [[ "$args" != *d* ]]; then
	echo "${echo_args[@]}" "$echo"
	#fi
	if [[ "$args" = *[ld]* ]]; then
		echo "$log" >> "$logs"
	fi
	if [[ "$args" = *e* ]]; then
		exit 1
	fi
}

declare -r prg_dir=~/.local/share/secrets.sh.d/"$date"
mkdir -vp "$prg_dir"
declare -r logs="$prg_dir/logs"
[[ ! -e "$logs" ]] || msg ei "Failed to create logs file at '$logs'"
touch "$logs"
msg il "Created log file at:"
msg rl "$logs"
msg il "===================="

function is_immutable () {
	[[ "$(lsattr "$1")" =~ ^....i ]]
}

function set_file () {
	local file="$1" mode="${2#-m}" owner group immutable="${5:-}"
	owner="$(getent passwd "${3#-o}" | cut -d: -f3)"
	group="$(getent group "${4#-g}" | cut -d: -f3)"
	local chmod='' chown='' chgrp='' chmutable=''
	local actual_mode actual_owner actual_group is_immutable=''
	if [[ -n "$mode" ]]; then
		local temp
		temp="$(mktemp "$prg_dir/tmp.XXXXXX")"
		chmod "${2#-m}" "$temp"
		mode="$(stat -c %a "$temp")"
		actual_mode="$(stat -c %a "$file")"
		[[ "$mode" = "$actual_mode" ]] || chmod=x
		rm -f "$temp"
	fi
	if [[ -n "$owner" ]]; then
		actual_owner="$(stat -c %u "$1")"
	       	if [[ "$actual_owner" != "$owner" ]]; then
			chown=x
		fi
	fi
	if [[ -n "$group" ]]; then
		actual_group="$(stat -c %g "$1")"
		if [[ "$actual_group" != "$group" ]]; then
			chgrp=x
		fi
	fi
	if is_immutable "$file"; then
		is_immutable=x
	fi
	[[ "$immutable" = + ]] && [[ -z "$is_immutable" ]] || chmutable=x
	[[ "$immutable" = - ]] && [[ -n "$is_immutable" ]] || chmutable=x
	if [[ -n "$chmod" ]] || [[ -n "$chown" ]] || [[ -n "$chgrp" ]] || [[ -n "$chmutable" ]]; then
		if [[ "$immutable" != n ]] && [[ -n "$is_immutable" ]]; then
			msg il "Removing attribute 'immutable' for '$file'"
			msg d chattr -V -i "$file"
		fi
		if [[ -n "$chmod" ]]; then 
			msg il "Changing permissions for '$file': '$actual_mode' => '$mode'"
			msg d chmod -v "$mode" "$file" || return $?
		fi
		if [[ -n "$chown" ]]; then
			msg il "Changing owner for '$file': '$actual_owner' => '$owner'"
			msg d chown -v "$owner" "$file" || return $?
		fi
		if [[ -n "$chgrp" ]]; then
			msg il "Changing group for '$file': '$actual_group' => '$group'"
			msg d chgrp -v "$group" "$file" || return $?
		fi
		if [[ "$immutable" = + ]]; then
				msg il "Setting attribute 'immutable' for '$file'"
				msg d chattr -V +i "$file"
		elif [[ "$immutable" != [n-] ]] && [[ -n "$is_immutable" ]]; then
			chattr -V +i "$file"
		fi
	else
		msg il "No changes required."
	fi
}

function backup () {
	local file="$1" backup mode_old=''
	backup="$prg_dir/backup-$file"
	msg d mkdir -vp "$(dirname "$backup")"
	if [[ ! -r "$file" ]]; then
		mode_old="$(stat -c %a "$file")"
		set_file "$file" -m400 -o -g
	fi
	msg d cp -v "$file" "$backup"
	msg d chattr -V +i "$backup"
	msg sl "Created backup of '$file' at '$backup'"
	[[ -z "$mode_old" ]] || set_file "$file" -m"$mode_old" -o -g
}

function secret_mk () {
	[[ $# -ge 1 ]] || usage
	local file owner='' group='' mode='000'
	while [[ $# != 0 ]]; do
		case "$1" in
			-m ) mode="$2" ;;
			-o ) owner="$(id -u "$2")" ;;
			-g ) group="$2" ;;
			-* ) usage ;;
			* ) break ;;
		esac
		shift 2
	done
	for file in "$@"; do
		if [[ -e "$file" ]]; then
			[[ -f "$file" ]] || msg el "Can't secure '$file' because it is not a regular file."
		fi
		{
			[[ -e "$file" ]] || msg d touch "$file"
			msg d set_file "$file" -m"$mode" -o"$owner" -g"$group" +
		} || msg el "'$file' was not secured because an error occured."
	done
}

function secret_not () {
	[[ $# -ge 1 ]] || usage
	local file owner group mode
	owner='' group='' mode=''
	while [[ $# != 0 ]]; do
		[[ "$1" != -* ]] || [[ $# -ge 2 ]] || usage
		case "$1" in
			-m ) mode="$2" ;;
			-o ) owner="$2" ;;
			-g ) group="$2" ;;
			-* ) usage ;;
			* ) break ;;
		esac
		shift 2
	done
	for file in "$@"; do
		{
			if [[ -e "$file" ]]; then
				[[ -f "$file" ]] || msg el "'$file' is not a regular file."
			else
				msg d touch "$file"
			fi
			msg d set_file "$file" -m"$mode" -o"$owner" -g"$group" -
		} || msg el "an error occured while unsecuring '$file'."
	done
}


function secret_rm () {
	[[ $# -gt 0 ]] || usage
	local file answer
	for file in "$@"; do
		[[ -e "$file" ]] || msg el "'$file' was not deleted because it does not exist."
		[[ -f "$file" ]] || msg el "'$file' was not deleted because it is not a regular file."
		msg in "You're about to remove the secret file '$file'.\nWrite 'I confirm.': "
		read -r answer
		if [[ "$answer" = 'I confirm.' ]]; then
			msg sl "'$file' will be deleted because of user input."
			if ! {
				msg d set_file "$file" -m -o -g - \
				&& msg d rm -vi "$file"
			}; then
				msg el "An error occured while trying to delete '$file'."
			fi
		else
			msg il "'$file' won't be deleted because of user input."
		fi
	done
}

function secret_edit () {
	[[ $# -ge 1 ]] || usage
	local file="$1" editor="${EDITOR:-${VI:-vim}}" temp backup owner mode mutable=+
	[[ -e "$file" ]] || msg el "'$file' does not exist."
	[[ -f "$file" ]] || msg el "'$file' is not a regular file."
	owner="$(stat -c %u "$file")"
	mode="$(stat -c %a "$file")"
	is_immutable "$file" || mutable=-
	temp="$(mktemp)" || msg el "Failed to create temporary file for editing."
	backup="$prg_dir/backup-$file"
	msg d backup "$file" || msg el "Failed to create backup file."
	msg sl "Saved current version of '$file' to '$backup'"
	msg d set_file "$file" -m600 -o"$UID" -g -
	msg d mv -vf "$file" "$temp"
	msg d "$editor" "$temp"
	msg d mv -v "$temp" "$file"
	msg d set_file "$file" -m"$mode" -o"$owner" -g "$mutable"
}

function secret_encrypt () {
	local key owner='' group='' mode='' immutable='' key_owner="$USER"
	while [[ $# -ne 0 ]]; do
		if [[ "$1" == -* ]] && [[ $# -lt 2 ]]; then
			usage
		fi
		case "$1" in
			-o ) owner="$2" ;;
			-g ) group="$2" ;;
			-m ) mode="$2" ;;
			-k ) key="$2" ;;
			-u ) key_owner="$2" ;;
			-i ) immutable="$2" ;;
			-* ) usage ;;
			* ) break ;;
		esac
		shift 2
	done
	if [[ $# -eq 0 ]]; then
		usage
	fi
	gpg_dir="$(getent passwd "$key_owner" | cut -d: -f 6)/.gnupg"
	local file encrypted old_mode
	for file in "$@"; do
		encrypted="$file.asc"
		while [[ -e "$encrypted" ]]; do
			read -rp "'$encrypted' already exists. Enter another file name: " encrypted
		done
		msg d backup "$file"
		old_mode="$(stat -c %a "$file")"
		msg d set_file "$file" -m400 -o -g
		gpg --pinentry-mode loopback --homedir "$gpg_dir" --output "$encrypted" --encrypt --sign --armor -r "$key" "$file"
		msg d set_file "$file" -m"$old_mode" -o -g
		msg d set_file "$encrypted" -m"${mode:-400}" -o"$owner" -g"$group" "${immutable:-+}"
	done
}

function secret_decrypt () {
	local owner='' group='' mode='' key='' key_owner="$USER"
	while [[ $# -ne 0 ]]; do
		if [[ "$1" == -* ]] && [[ $# -lt 2 ]]; then
			usage
		fi
		case "$1" in
			-o ) owner="$2" ;;
			-g ) group="$2" ;;
			-m ) mode="$2" ;;
			-k ) key="$2" ;;
			-u ) key_owner="$2" ;;
			-* ) usage ;;
			* ) break ;;
		esac
		shift 2
	done
	local file gpg_dir
	gpg_dir="$(getent passwd "$key_owner" | cut -d: -f6)/.gnupg"
	for file in "$@"; do
		local decrypted old_mode='' old_owner=''
		if [[ ! -r "$file" ]]; then
			read -r old_mode old_owner <<<"$(stat -c '%a %u' "$file")"
			msg d set_file "$file" -m400 -o"$USER" -g
		fi
		decrypted="${file%.asc}"
		while [[ -e "$decrypted" ]]; do
			read -rp "'$decrypted' already exists. Enter another file name: " decrypted
		done
		gpg --homedir "$gpg_dir" --pinentry-mode loopback --output "$decrypted" --decrypt "$file"
		if [[ -n "$old_mode" ]] || [[ -n "$old_owner" ]]; then
			msg d set_file "$file" -m"$old_mode" -o"$old_owner" -g
		fi
		msg d set_file "$decrypted" -m"$mode" -o"$owner"  -g"$group"
	done
}

case "$1" in
	mk|rm|not|edit|encrypt|decrypt )
		cmd="$1"
		shift
		secret_"$cmd" "$@"
		;;
	* ) usage ;;
esac
