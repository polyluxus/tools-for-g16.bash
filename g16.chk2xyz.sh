#!/bin/bash
#
#hlp A very quick script to transform a checkpointfile
#hlp to a formatted checkpointfile and then to xyz 
#hlp coordinates using Open Babel.
#hlp Usage: $scriptname [option] <checkpointfile(s)>
#hlp Distributed with tools-for-g16.bash $version ($versiondate)
# 
# This was last updated with 
version="0.0.5"
versiondate="2018-05-08"
# of tools-for-g16.bash

#standard commands:
g16_formchk_cmd="wrapper.g16 formchk -3" # ( Current workaround )
obabel_cmd="obabel"

#
# Print logging information and warnings nicely.
# If there is an unrecoverable error: display a message and exit.
#

message ()
{
    if (( stay_quiet <= 0 )) ; then
      echo "INFO   : " "$*" >&3
    else
      debug "(info   ) " "$*"
    fi
}

warning ()
{
    if (( stay_quiet <= 1 )) ; then
      echo "WARNING: " "$*" >&2
    else
      debug "(warning) " "$*"
    fi
    return 1
}

fatal ()
{
    if (( stay_quiet <= 2 )) ; then 
      echo "ERROR  : " "$*" >&2
    else
      debug "(error  ) " "$*"
    fi
    exit 1
}

debug ()
{
    echo "DEBUG  : " "$*" >&4
}    

#
# Print some helping commands
# The lines are distributed throughout the script and grepped for
#

helpme ()
{
    local line
    local pattern="^[[:space:]]*#hlp[[:space:]]?(.*)?$"
    while read -r line; do
      [[ "$line" =~ $pattern ]] && eval "echo \"${BASH_REMATCH[1]}\""
    done < <(grep "#hlp" "$0")
    exit 0
}

# 
# Let's know where the script is and how it is actually called
#

get_absolute_location ()
{
    # Resolves the absolute location of parameter and returns it
    # Taken from https://stackoverflow.com/a/246128/3180795
    local resolve_file="$1" description="$2" 
    local link_target directory_name filename resolve_dir_name 
    debug "Getting directory for '$resolve_file'."
    #  resolve $resolve_file until it is no longer a symlink
    while [[ -h "$resolve_file" ]]; do 
      link_target="$(readlink "$resolve_file")"
      if [[ $link_target == /* ]]; then
        debug "File '$resolve_file' is an absolute symlink to '$link_target'"
        resolve_file="$link_target"
      else
        directory_name="$(dirname "$resolve_file")" 
        debug "File '$resolve_file' is a relative symlink to '$link_target' (relative to '$directory_name')"
        #  If $resolve_file was a relative symlink, we need to resolve 
        #+ it relative to the path where the symlink file was located
        resolve_file="$directory_name/$link_target"
      fi
    done
    debug "File is '$resolve_file'" 
    filename="$(basename "$resolve_file")"
    debug "File name is '$filename'"
    resolve_dir_name="$(dirname "$resolve_file")"
    directory_name="$(cd -P "$(dirname "$resolve_file")" && pwd)"
    if [[ "$directory_name" != "$resolve_dir_name" ]]; then
      debug "$description '$directory_name' resolves to '$directory_name'."
    fi
    debug "$description is '$directory_name'"
    if [[ -z $directory_name ]] ; then
      directory_name="."
    fi
    echo "$directory_name/$filename"
}

get_absolute_filename ()
{
    # Returns only the filename
    local resolve_file="$1" description="$2" return_filename
    return_filename=$(get_absolute_location "$resolve_file" "$description")
    return_filename=${return_filename##*/}
    echo "$return_filename"
}

get_absolute_dirname ()
{
    # Returns only the directory
    local resolve_file="$1" description="$2" return_dirname
    return_dirname=$(get_absolute_location "$resolve_file" "$description")
    return_dirname=${return_dirname%/*}
    echo "$return_dirname"
}

#
# Get settings from configuration file
#

test_rc_file ()
{
  local test_runrc="$1"
  debug "Testing '$test_runrc' ..."
  if [[ -f "$test_runrc" && -r "$test_runrc" ]] ; then
    echo "$test_runrc"
    return 0
  else
    debug "... missing."
    return 1
  fi
}

get_rc ()
{
  local test_runrc_dir test_runrc_loc return_runrc_loc runrc_basename
  # The rc should have some similarity with the actual scriptname
  local runrc_basename="$scriptbasename" runrc_bundle="g16.tools"
  while [[ ! -z $1 ]] ; do
    test_runrc_dir="$1"
    shift
    if test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_basename}rc")" ; then
      return_runrc_loc="$test_runrc_loc" 
      debug "   (found) return_runrc_loc=$return_runrc_loc"
      continue
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_basename}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_bundle}rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_bundle}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    fi
  done
  debug "(returned) return_runrc_loc=$return_runrc_loc"
  echo "$return_runrc_loc"
}

#
# Test, whether we can access the given file/directory
#

is_file ()
{
    [[ -f $1 ]]
}

is_readable ()
{
    [[ -r $1 ]]
}

is_readable_file_or_exit ()
{
    is_file "$1"     || fatal "Specified file '$1' is no file or does not exist."
    is_readable "$1" || fatal "Specified file '$1' is not readable."
}

is_readable_file_and_warn ()
{
    is_file "$1"     || warning "Specified file '$1' is no file or does not exist."
    is_readable "$1" || warning "Specified file '$1' is not readable."
}

#
# Check if file exists and prevent overwriting
#

test_file_location ()
{
    local savesuffix=1 file_return="$1"
    debug "Checking file: $file_return"
    if ! is_file "$file_return" ; then
      echo "$file_return"
      debug "There is no file '$file_return'. Return 0."
      return 0
    else
      while is_file "${file_return}.${savesuffix}" ; do
        (( savesuffix++ ))
        debug "The file '${file_return}.${savesuffix}' exists."
      done
      warning "File '$file_return' exists."
      echo "${file_return}.${savesuffix}"
        debug "There is no file '${file_return}.${savesuffix}'. Return 1."
      return 1
    fi
}

backup_file ()
{
    local move_message move_source="$1" move_target="$2"
    debug "Will attempt: mv -v $move_source $move_target"
    move_message="$(mv -v "$move_source" "$move_target")" || fatal "Backup went wrong."
    message "File will be backed up."
    message "$move_message"
}

backup_if_exists ()
{
    local move_target
    move_target=$(test_file_location "$1") && return
    backup_file "$1" "$move_target"
}

#
# Format checkpoint file, write xyz coordinates
# a.k.a. run the programs
#

format_one_checkpoint ()
{
    local returncode=0
    local input_chk="$1"
    local output_fchk="${input_chk%.*}.fchk"
    local output_xyz="${input_chk%.*}.xyz"
    local g16_output obabel_output
    
    backup_if_exists "$output_fchk"
    backup_if_exists "$output_xyz"
    
    # Run the programs
    g16_output=$($g16_formchk_cmd "$input_chk" "$output_fchk" 2>&1) || returncode="$?"
    if (( returncode != 0 )) ; then
      warning "There was an issue with formatting the checkpointfile."
      debug "Output: $g16_output"
      return "$returncode"
    else
      message "Formatted '$input_chk'." 
      debug "$g16_output"
    fi

    obabel_output=$($obabel_cmd -ifchk "$output_fchk" -oxyz -O"$output_xyz" 2>&1) || (( returncode+=$? ))
    if (( returncode != 0 )) ; then
      warning "There was an issue with writing the coordinates."
      debug "Output: $obabel_output"
      return "$returncode"
    else
      message "Written '$output_xyz'."
      debug "$obabel_output"
    fi
}

format_only ()
{
    # run only for commandline arguments
    is_readable_file_and_warn "$1" && format_one_checkpoint "$1" || return $?
}

format_all ()
{
    # run over all checkpoint files
    local input_chk returncode=0
    # truncate first two directories 
    message "Working on all checkpoint files in ${PWD#\/*\/*\/}." 
    for input_chk in *.chk; do
      [[ "$input_chk" == "*.chk" ]] && fatal "There are no checkpointfiles in this directory."
      format_only "$input_chk" || (( returncode+=$? ))
    done
    return $returncode
}

#
# MAIN SCRIPT
#

# Save how it was called
script_invocation_spell="$0 $*"

# Sent logging information to stdout
exec 3>&1

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

# Set defaults
exit_status=0
skip_list="false"
stay_quiet=0

# Who are we and where are we?
scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
debug "Script is called '$scriptname'"
# remove scripting ending (if present)
scriptbasename=${scriptname%.sh} 
debug "Base name of the script is '$scriptbasename'"
scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
debug "Script is located in '$scriptpath'"

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
subg16_rc_loc="$(get_rc "$scriptpath" "/home/$USER" "$PWD")"
debug "subg16_rc_loc=$subg16_rc_loc"

# Load custom settings from the rc

if [[ ! -z $subg16_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-g16.bash/g16.tools.rc 
  . "$subg16_rc_loc"
  message "Configuration file '$subg16_rc_loc' applied."
else
  debug "No custom settings found."
fi


(( $# == 0 )) &&  fatal "No checkpointfile specified."

# Initialise options
OPTIND="1"

while getopts :fh options ; do
  case $options in
    #hlp OPTIONS:
    #hlp   -f      Formats all checkpointfiles that are found in the current directory
    f) format_all || exit_status=$?
       skip_list="true"
       ;;
    #hlp   -h      Prints this help text
    h) helpme ;; 

   \?) fatal "Invalid option: -$OPTARG." ;;

    :) fatal "Option -$OPTARG requires an argument." ;;

  esac
done

shift $(( OPTIND - 1 ))

if [[ $skip_list != "true" ]] ; then
  while [[ ! -z $1 ]] ; do
    format_only "$1" || (( exit_status+=$? ))
    shift
  done
fi

(( exit_status == 0 )) || fatal "There have been one or more errors."

message "$scriptname is part of tools-for-g16.bash $version ($versiondate)"
debug "$script_invocation_spell"
