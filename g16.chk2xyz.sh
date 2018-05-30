#!/bin/bash
#
#hlp A very quick script to transform a checkpointfile
#hlp to a formatted checkpointfile and then to xyz 
#hlp coordinates using Open Babel.
#hlp Usage: $scriptname [option] <checkpointfile(s)>
#hlp Distributed with $softwarename $version ($versiondate)
# 

source ./resources/default_variables.sh
source ./resources/messaging.sh
source ./resources/locations.sh
source ./resources/rcfiles.sh
source ./resources/test_files.sh

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

message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
