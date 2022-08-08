#! /bin/bash
# shellcheck disable=SC2312,SC2310,SC2250

set -ue

# shellcheck disable=SC2155
declare -r date="$(date +%F_%T)"


function usage () {
	cat <<EOF
Usage:
	$0 [OPTION ...] COMMAND [ARG ...]
Options:
	-no-color
		Disable colored output.
	-verbose|-v
		Show more informations.
	-debug
		Show debug messages.
	-trace
		Enable Bash 'xtrace' option. Intended for debugging.
Commands:
	mk [-o OWNER ] [-g GROUP] [-m MODE] FILES
		Protect FILES by setting the 'immutable' attribute on them.
	not [-o OWNER ] [-g GROUP] [-m MODE] FILES
		Remove this attribute.
	rm FILES ...
		Remove files with this attribute.
	edit FILE
		Edit a file with this attribute.
	encrypt [-o OWNER] [-g GROUP] [-m MODE] [-k KEY] [-u KEY_OWNER] [-i -|+] FILE ...
		Encrypt a file.
	decrypt [-o OWNER] [-g GROUP] [-m MODE] [-u KEY_OWNER] FILE ...
		Decrypt a file.
Note: When FILE begins with a dash (-),
you must prefix it with './' else it will be interpreted as an option.
EOF
	exit 1
}


function display () {
	echo "${colors[${FUNCNAME[1]}]}$*${colors[reset]}"
}

function log () {
	local trace="${FUNCNAME[*]}"
	echo "[${FUNCNAME[1]}] ${trace// />}: ${*//$'\n'/$'\n\t'}" >> "$logs"
}

function success () {
	display "$*"
	log "$*"
}

function error () {
	display "$*"
	log "$*"
	exit 1
}

function info () {
	display "$*"
	log "$*"
}

function verbose () {
	if [[ -n "$verbose" ]]; then
		display "$*"
	fi
	log "$*"
}

function debug () {
	local cmd cmd_out exit_status
	declare -a cmd=("$@")
	cmd_out="$prg_dir/output.XXXX"
	if [[ -n "$debug" ]]; then
		display "Running command: ${cmd[*]}"
	fi
	log "running command: ${cmd[*]}"
	"${cmd[@]}" |& tee "$cmd_out"
	declare -i exit_status="${PIPESTATUS[0]}"
	log "exit status: $exit_status"
	log "command output:"
	log "$(wc -l "$cmd_out") lines"
	log "$(cat "$cmd_out")"
	log "==============="
	return "$exit_status"
}



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
			verbose "Setting 'immutable' attribute on '$file'"
			debug chattr -V +i "$file"
		fi
		if [[ -n "$chmod" ]]; then 
			verbose "Changing permissions for '$file': '$actual_mode' => '$mode'"
			debug chmod -v "$mode" "$file"
		fi
		if [[ -n "$chown" ]]; then
			verbose "Changing owner for '$file': '$actual_owner' => '$owner'"
			debug chown -v "$owner" "$file"
		fi
		if [[ -n "$chgrp" ]]; then
			verbose "Changing group for '$file': '$actual_group' => '$group'"
			debug chgrp -v "$group" "$file"
		fi
		if [[ "$immutable" = + ]] || { [[ "$immutable" != [n-] ]] && [[ -n "$is_immutable" ]]; }; then
			verbose "Removing 'immutable' attribute on '$file'"
			debug chattr -V -i "$file"
		fi
	else
		verbose "No changes required."
	fi
}

function backup () {
	local file="$1" backup mode_old=''
	backup="$prg_dir/backup-$file"
	debug mkdir -vp "$(dirname "$backup")"
	if [[ ! -r "$file" ]]; then
		mode_old="$(stat -c %a "$file")"
		set_file "$file" -m400 -o -g
	fi
	debug cp -v "$file" "$backup"
	verbose "Setting 'immutable' attribute on '$backup'"
	debug chattr -V +i "$backup"
	info "Created backup of '$file' at '$backup'"
	if [[ -n "$mode_old" ]]; then
		set_file "$file" -m"$mode_old" -o -g
	fi
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
			[[ -f "$file" ]] || error "Can't secure '$file' because it is not a regular file."
		fi
		if
			[[ -e "$file" ]] || touch "$file"
			set_file "$file" -m"$mode" -o"$owner" -g"$group" +
		then
			success "Secured '$file'."
		else
			error "'$file' was not secured because an error occured."
		fi
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
				[[ -f "$file" ]] || error "'$file' is not a regular file."
			else
				touch "$file"
			fi
			set_file "$file" -m"$mode" -o"$owner" -g"$group" -
		} || error "an error occured while unsecuring '$file'."
	done
}

function secret_rm () {
	[[ $# -gt 0 ]] || usage
	local file answer
	for file in "$@"; do
		[[ -e "$file" ]] || error "can't delete '$file' because it does not exist."
		[[ -f "$file" ]] || error "can't delete '$file' because it is not a regular file."
		info "You're about to remove the secret file '$file'.\nWrite 'I confirm.': "
		read -r answer
		if [[ "$answer" = 'I confirm.' ]]; then
			info "'$file' will be deleted."
			if
				set_file "$file" -m -o -g - &&
				debug rm -vi "$file"
			then
				success "Deleted '$file'."
			else
				error "An error occured while trying to delete '$file'."
			fi
		else
			info "'$file' won't be deleted."
		fi
	done
}

function secret_edit () {
	[[ $# -ge 1 ]] || usage
	local file="$1" editor="${EDITOR:-${VI:-vim}}" temp backup owner mode mutable=+
	[[ -e "$file" ]] || error "'$file' does not exist."
	[[ -f "$file" ]] || error "'$file' is not a regular file."
	owner="$(stat -c %u "$file")"
	mode="$(stat -c %a "$file")"
	is_immutable "$file" || mutable=-
	temp="$(mktemp)" || error "Failed to create temporary file for editing."
	backup="$prg_dir/backup-$file"
	backup "$file" || error "Failed to create backup file."
	info "Saved current version of '$file' to '$backup'"
	set_file "$file" -m600 -o"$UID" -g -
	debug mv -vf "$file" "$temp"
	debug "$editor" "$temp"
	debug mv -v "$temp" "$file"
	set_file "$file" -m"$mode" -o"$owner" -g "$mutable"
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
		backup "$file"
		old_mode="$(stat -c %a "$file")"
		set_file "$file" -m400 -o -g
		debug gpg --pinentry-mode loopback --homedir "$gpg_dir" --output "$encrypted" --encrypt --sign --armor -r "$key" "$file"
		set_file "$file" -m"$old_mode" -o -g
		set_file "$encrypted" -m"${mode:-400}" -o"$owner" -g"$group" "${immutable:-+}"
	done
}

function secret_decrypt () {

	local owner='' group='' mode='' key_owner="$USER"
	while [[ $# -ne 0 ]]; do
		if [[ "$1" == -* ]] && [[ $# -lt 2 ]]; then
			usage
		fi
		case "$1" in
			-o ) owner="$2" ;;
			-g ) group="$2" ;;
			-m ) mode="$2" ;;
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
			set_file "$file" -m400 -o"$USER" -g
		fi
		decrypted="${file%.asc}"
		while [[ -e "$decrypted" ]]; do
			read -rp "'$decrypted' already exists. Enter another file name: " decrypted
		done
		debug gpg --homedir "$gpg_dir" --pinentry-mode loopback --output "$decrypted" --decrypt "$file"
		if [[ -n "$old_mode" ]] || [[ -n "$old_owner" ]]; then
			set_file "$file" -m"$old_mode" -o"$old_owner" -g
		fi
		set_file "$decrypted" -m"$mode" -o"$owner"  -g"$group"
	done
}


# parse arguments before the command
no_color='' verbose='' debug='' trace=''
while [[ $# -ne 0 ]]; do
	case "$1" in
		-no-color ) no_color=x ;;
		-v | -verbose ) verbose=x ;;
		-debug ) debug=x ;;
		-trace ) trace=x ;;
		-* ) usage ;;
		* ) break ;;
	esac
	shift
done

if [[ -n "$trace" ]]; then
	set -x
fi

if [[ $# -eq 0 ]]; then
	usage
fi


# define text formatting for messages
if [[ -z "$no_color" ]]; then
	declare -rA colors=(
		[error]=$'\e[1;37;41m'
		[success]=$'\e[1;30;42m'
		[info]=$'\e[96m'
		[verbose]=$'\e[34m'
		[debug]=$'\e[2m'
		[reset]=$'\e[0m'
	)
else
	declare -rA colors=(
		[error]=''
		[success]=''
		[info]=''
		[verbose]=''
		[debug]=''
		[reset]=''
	)
fi


# run the command (if it exist)
case "$1" in
	mk|rm|not|edit|encrypt|decrypt )
	
		# create logs file
		declare -r prg_dir=~/.local/share/secrets.sh.d/"$date"
		mkdir -vp "$prg_dir"
		declare -r logs="$prg_dir/logs"
		if [[ -e "$logs" ]]; then
			_logs="$logs"
			logs="$(tty)"
			error "Logs file at '$_logs' already exists."
		fi
		touch "$logs"
		info "Created log file at '$logs'"
		
		main_cmd="$1"
		shift
		secret_"$main_cmd" "$@"
		;;

	* ) usage ;;
esac
