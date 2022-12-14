#! /bin/bash
# shellcheck disable=SC2250


# MIT License
# 
# Copyright (c) 2022 me-mariosteve
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


set -o nounset -o errexit
shopt -s inherit_errexit

# Put nanoseconds in the date so the script can be run
# multiple times a second, else the directory that
# should be used would be created and used by another
# process running this script.
# shellcheck disable=SC2155
declare -r date="$(date +%F_%T.%N)"



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
	encrypt [-o OWNER] [-g GROUP] [-m MODE] -k KEY [-u KEY_OWNER] [-i -|+] FILE ...
		Encrypt a file.
	decrypt [-o OWNER] [-g GROUP] [-m MODE] [-u KEY_OWNER] FILE ...
		Decrypt a file.
Note: When FILE begins with a dash (-),
you must prefix it with './' else it will be interpreted as an option.
EOF
	exit 1
}



## Function used to display and log messages.

function display () {
	echo "${colors[${FUNCNAME[1]}]}$*${colors[reset]}"
}
function log () {
	local trace="${FUNCNAME[*]}"
	echo "[${FUNCNAME[1]}] ${trace// />}: ${*//$'\n'/$'\n\t'}" >> "$log_file"
}
function success () {
	display "$*"
	log "$*"
}
function error () {
	display "$*"
	log "$*"
	exit "${2:-1}"
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
	cmd_out="$current_run_dir/output.XXXX"
	if [[ -n "$debug" ]]; then
		display "Running command: ${cmd[*]}"
	fi
	log "running command: ${cmd[*]}"
	# temporarely disable this option so when ${cmd[@]} fails the script won't stop
	shopt -u inherit_errexit
	"${cmd[@]}" |& tee "$cmd_out" || true
	declare -i exit_status="${PIPESTATUS[0]}"
	shopt -s inherit_errexit
	log "exit status: $exit_status
command output:
$(wc -l "$cmd_out" || true) lines
$(cat "$cmd_out" || true)
==============="
	return "$exit_status"
}

 

# Ask the name of a file that doesn't exist.
# If it exists, asks the user if he wants to overwrite it
# else asks again.
function ask_filename () {
	local attempt="$1"
	while [[ -e "$attempt" ]]; do
		read -rp "'$attempt' already exists. Please enter another file name, or the same it overwrite it: "
		if [[ "$REPLY" = "$attempt" ]]; then
			break
		fi
		attempt="$REPLY"
	done
	echo "$attempt"
}


 
function is_immutable () {
	# is_immutable FILE
	# Exit with code 0 if FILE is immutable,
	# else 1.
	[[ "$(lsattr "$1" || true)" =~ ^....i ]]
}


function set_file () {
	# set_file FILE -m[MODE] -o[OWNER] -g[GROUP] [+|-]
	# - '-m', '-o' and '-g' must be present even without the argument.
	# - If an argument of MODE, OWNER or GROUP is not given,
	#   then the corresponding property of the file won't be changed.
	# - If there is '+' at the end, the file will have the immutable attribute;
	#   if there is '-' it this attribute won't be set,
	#   and if there is nothing it won't be changed.
	
	local file="$1" mode="${2#-m}" owner group immutable="${5:-}"
	owner="$(getent passwd "${3#-o}" | cut -d: -f3)"
	group="$(getent group "${4#-g}" | cut -d: -f3)"
	local chmod='' chown='' chgrp='' chmutable=''
	local actual_mode actual_owner actual_group is_immutable=''
	
	# Find what needs to be changed.
	if [[ -n "$mode" ]]; then
		local temp
		temp="$(mktemp "$current_run_dir/tmp.XXXXXX")"
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
	if { [[ "$immutable" = + ]] && [[ -z "$is_immutable" ]]; } ||
		{ [[ "$immutable" = - ]] && [[ -n "$is_immutable" ]]; }
	then
		chmutable=x
	fi
	
	if [[ -n "$chmod" ]] || [[ -n "$chown" ]] || [[ -n "$chgrp" ]] || [[ -n "$chmutable" ]]; then
		if [[ -n "$is_immutable" ]]; then
			verbose "Removing 'immutable' attribute on '$file'"
			chattr -i "$file"
		fi

		# Make the required changes.
		if [[ -n "$chmod" ]]; then 
			verbose "Changing permissions for '$file': '$actual_mode' => '$mode'"
			chmod "$mode" "$file"
		fi
		if [[ -n "$chown" ]]; then
			verbose "Changing owner for '$file': '$actual_owner' => '$owner'"
			chown "$owner" "$file"
		fi
		if [[ -n "$chgrp" ]]; then
			verbose "Changing group for '$file': '$actual_group' => '$group'"
			chgrp "$group" "$file"
		fi
		if { [[ -n "$chmutable" ]] && [[ "$immutable" = + ]]; } ||
			{ [[ -z "$chmutable" ]] && [[ -n "$is_immutable" ]]; }
		then
			verbose "Setting 'immutable' attribute on '$file'"
			chattr +i "$file"
		fi

	else
		verbose "No changes required."
	fi
}



function backup () {
	# backup FILE
	# Save a readonly copy of FILE under $current_run_dir.
	local file="$1" backup mode_old=''
	backup="$current_run_dir/backup-$file"
	mkdir -p "$(dirname "$backup")"
	if [[ ! -r "$file" ]]; then
		mode_old="$(stat -c %a "$file")"
		set_file "$file" -m400 -o -g
	fi
	debug cp -v "$file" "$backup"
	verbose "Setting 'immutable' attribute on '$backup'"
	chattr +i "$backup"
	info "Created backup of '$file' at '$backup'"
	if [[ -n "$mode_old" ]]; then
		set_file "$file" -m"$mode_old" -o -g
	fi
}



# The commands of this script:
# mk, not, rm, edit, encrypt, decrypt.
# Read the help message for usage.

function secret_mk () {
	# parse options
	[[ $# -ge 1 ]] || usage
	local file owner='' group='' mode=''
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
		then
			set_file "$file" -m"$mode" -o"$owner" -g"$group" +
			success "Secured '$file'."
		else
			error "'$file' was not secured because an error occured."
		fi
	done
}


function secret_not () {
	# parse options
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
		if [[ -e "$file" ]]; then
			[[ -f "$file" ]] || error "'$file' is not a regular file."
		else
			touch "$file"
		fi
		set_file "$file" -m"$mode" -o"$owner" -g"$group" - || error "An error occured while unsecuring '$file'."
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
			{
				set_file "$file" -m -o -g -
				debug rm -vi "$file"
			} || error "An error occured while trying to delete '$file'."
			success "Deleted '$file'."
		else
			info "'$file' won't be deleted."
		fi
	done
}


function secret_edit () {
	[[ $# -ge 1 ]] || usage
	local file="$1" editor="${EDITOR:-${VI:-vim}}" temp backup owner mode mutable
	[[ -e "$file" ]] || error "'$file' does not exist."
	[[ -f "$file" ]] || error "'$file' is not a regular file."
	# get informations about the file to edit
	owner="$(stat -c %u "$file")"
	mode="$(stat -c %a "$file")"
	if is_immutable "$file"; then
		mutable=+
	else
		mutable=-
	fi
	# create temporary file for editing
	temp="$(mktemp)" || error "Failed to create temporary file for editing."
	# backup the file
	backup="$current_run_dir/backup-$file"
	backup "$file" || error "Failed to create backup file."
	info "Saved current version of '$file' to '$backup'"
	# prepare to edit
	set_file "$file" -m600 -o"$UID" -g -
	debug mv -vf "$file" "$temp"
	debug "$editor" "$temp"
	debug mv -v "$temp" "$file"
	set_file "$file" -m"$mode" -o"$owner" -g "$mutable"
}


function secret_encrypt () {
	# parse options
	local key='' owner='' group='' mode='' immutable='' key_owner="$USER"
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
	if [[ $# -eq 0 ]] || [[ -z "$key" ]]; then
		usage
	fi
	gpg_dir="$(getent passwd "$key_owner" | cut -d: -f 6)/.gnupg"
	local file encrypted old_mode

	# encrypt the files
	for file in "$@"; do
		encrypted="$(ask_filename "$file.asc")"
		old_mode="$(stat -c %a "$file")"
		set_file "$file" -m400 -o -g
		debug gpg --pinentry-mode loopback --homedir "$gpg_dir" --output "$encrypted" --encrypt --sign --armor -r "$key" "$file"
		set_file "$file" -m"$old_mode" -o -g
		set_file "$encrypted" -m"${mode:-400}" -o"$owner" -g"$group" "${immutable:-+}"
	done
}


function secret_decrypt () {
	# parse options
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
	
	# decrypt the files
	for file in "$@"; do
		local decrypted old_mode='' old_owner=''
		if [[ ! -r "$file" ]]; then
			read -r old_mode old_owner <<<"$(stat -c '%a %u' "$file" || true)"
			set_file "$file" -m400 -o"$USER" -g
		fi
		decrypted="$(ask_filename "${file%.asc}")"
		debug gpg --homedir "$gpg_dir" --pinentry-mode loopback --output "$decrypted" --decrypt "$file"
		if [[ -n "$old_mode" ]] || [[ -n "$old_owner" ]]; then
			set_file "$file" -m"$old_mode" -o"$old_owner" -g
		fi
		set_file "$decrypted" -m"$mode" -o"$owner"  -g"$group"
	done
}



# parse global options
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

# no command
if [[ $# -eq 0 ]]; then
	usage
fi

if [[ -n "$trace" ]]; then
	set -x
fi

# define aliases so we don't have to write 'debug' everytime
alias chmod='debug chmod'
alias chown='debug chown'
alias chgrp='debug chgrp'
alias chattr='debug chattr'

# verbose option for the used commands
if [[ -n "$verbose" ]]; then
	alias mkdir='mkdir -v'
	alias chmod='chmod -v'
	alias chown='chown -v'
	alias chgrp='chgrp -v'
	alias chattr='chattr -V'
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


# Run the command if it exist.
case "$1" in
	mk|rm|not|edit|encrypt|decrypt )
	
		# create logs file
		declare -r main_prg_dir=~/.local/share/secrets.sh.d/
		declare -r current_run_dir="$main_prg_dir/$date"
		if [[ -e "$current_run_dir" ]]; then
			log_file="$(tty)"
			error "'$current_run_dir' should have been used as the directory for the current
execution of this program and nothing else, but it already exists."
		fi
		mkdir -p "$current_run_dir"
		log_file_attempt="$current_run_dir/logs"
		if [[ -e "$log_file_attempt" ]]; then
			log_file="$(tty)"
			error "Logs file at '$log_file_attempt' already exists."
		fi
		declare log_file="$log_file_attempt"
		touch "$log_file"
		info "Created log file at '$log_file'"
		
		# run the command
		main_cmd="$1"
		shift
		secret_"$main_cmd" "$@"
		;;

	* ) usage ;;
esac
