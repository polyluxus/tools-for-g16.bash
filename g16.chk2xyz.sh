#!/bin/bash
#
#hlp   A very quick script to transform a checkpointfile
#hlp   to a formatted checkpointfile and then to xyz 
#hlp   coordinates using Open Babel.
#hlp   Usage: $scriptname [option] <checkpointfile(s)>
#hlp
# 

#
# Generic functions to find the scripts 
# (Copy of ./resources/locations.sh)
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

get_scriptpath_and_source_files ()
{
    local error_count tmplog line tmpmsg
    tmplog=$(mktemp tmp.XXXXXXXX) 
    # Who are we and where are we?
    scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
    debug "Script is called '$scriptname'"
    # remove scripting ending (if present)
    scriptbasename=${scriptname%.sh} 
    debug "Base name of the script is '$scriptbasename'"
    scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
    debug "Script is located in '$scriptpath'"
    resourcespath="$scriptpath/resources"
    
    if [[ -d "$resourcespath" ]] ; then
      debug "Found library in '$resourcespath'."
    else
      (( error_count++ ))
    fi
    
    # Import default variables
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0
    
    # Import other functions
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))

    if (( error_count > 0 )) ; then
      echo "ERROR: Unable to locate library functions. Check installation." >&2
      echo "ERROR: Expect functions in '$resourcespath'."
      debug "Errors caused by:"
      while read -r line || [[ -n "$line" ]] ; do
        debug "$line"
      done < "$tmplog"
      tmpmsg=$(rm -v "$tmplog")
      debug "$tmpmsg"
      exit 1
    else
      tmpmsg=$(rm -v "$tmplog")
      debug "$tmpmsg"
    fi
}

#
# Specific functions for this script only
#

#
# Format checkpoint file, write xyz coordinates
# a.k.a. run the programs
#

format_one_checkpoint ()
{
    local returncode=0
    local input_chk="$1"
    local use_input_chk

    if use_input_chk=$(is_readable_file_and_warn "$input_chk") ; then
      debug "Operating on '$use_input_chk'."
    else
      debug "Failed on '$use_input_chk'."
      return 1
    fi
    
    local output_fchk="${use_input_chk%.*}.fchk"
    local output_xyz="${use_input_chk%.*}.xyz"
    local g16_output g16_formchk_args obabel_output
    debug "global variables used: 'g16_formchk_cmd=$g16_formchk_cmd' 'g16_formchk_opts=$g16_formchk_opts'"

    backup_if_exists "$output_fchk"
    backup_if_exists "$output_xyz"
    
    # Run the programs
    g16_formchk_args=( "$g16_formchk_opts" "$use_input_chk" "$output_fchk" )

    debug "Command: $g16_formchk_cmd ${g16_formchk_args[*]} 2>&1"
    g16_output=$($g16_formchk_cmd "${g16_formchk_args[@]}" 2>&1) || returncode="$?"
    if (( returncode != 0 )) ; then
      warning "There was an issue with formatting the checkpointfile."
      debug "Output: $g16_output"
      return "$returncode"
    else
      message "Formatted '$input_chk'." 
      debug "$g16_output"
    fi

    debug "Global variables used: 'obabel_cmd=$obabel_cmd'"
    debug "Command: $obabel_cmd -ifchk \"$output_fchk\" -oxyz -O\"$output_xyz\" 2>&1"
    # Options for obabel to read a formatted checkpoint and output xyz coordinates
    
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
    local tested_file
    # run only for commandline arguments
    tested_file=$(is_readable_file_and_warn "$1") || return $?
    format_one_checkpoint "$tested_file" || return $?
}

###   get_all_checkpoint ()
###   {
###       # See [How to return an array in bash without using globals?](https://stackoverflow.com/a/49971213/3180795)
###       # Works only in Bash 4.3 :(
###       local -n arrayname="$1"
###       # run over all checkpoint files
###       local test_chk returncode=0
###       # truncate first two directories 
###       message "Finding all checkpoint files in ${PWD#\/*\/*\/}." 
###       for test_chk in *.chk; do
###         if [[ "$test_chk" == "*.chk" ]] ; then
###           warning "There are no checkpointfiles in this directory."
###           returncode=1
###         fi
###         arrayname+=("$test_chk")
###       done
###       return $returncode
###   }

format_list ()
{
    # run over all checkpoint files
    local input_chk returncode=0
    # truncate first two directories 
    for input_chk in "$@" ; do
      format_only "$input_chk" || (( returncode+=$? ))
    done
    return $returncode
}

#
# MAIN SCRIPT
#

# If this script is sourced, return before executing anything
(( ${#BASH_SOURCE[*]} > 1 )) && return 0

# Save how script was called
script_invocation_spell="$0 $*"

# Sent logging information to stdout
exec 3>&1

# Need to define debug function if unknown
if ! command -v debug ; then
  debug () {
    echo "DEBUG  : " "$*" >&4
  }
fi

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

get_scriptpath_and_source_files || exit 1

# Abort if neither options nor a file list is given
(( $# == 0 )) &&  fatal "No checkpointfile specified."

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
g16_tools_rc_loc="$(get_rc "$scriptpath" "/home/$USER" "$PWD")"
debug "g16_tools_rc_loc=$g16_tools_rc_loc"

# Load custom settings from the rc

if [[ ! -z $g16_tools_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-g16.bash/g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '$g16_tools_rc_loc' applied."
else
  debug "No custom settings found."
fi

# Initialise options
debug "Initialising option index."
OPTIND="1"

while getopts :fh options ; do
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -f      Formats all checkpointfiles that are found in the current directory
    #hlp
    f) 
       ### get_all_checkpoint checkpoint_list # Needs Bash > 4.3
       debug "Executing for directory; looking for all checkpoint files."
       mapfile -t checkpoint_list < <( ls ./*.chk 2> /dev/null ) 
       debug "Found: ${checkpoint_list[*]}"
       (( ${#checkpoint_list[*]} == 0 )) &&  warning "No checkpoint files found in this directory."
       ;;
    #hlp     -h      Prints this help text
    #hlp
    h) helpme ;; 

   \?) fatal "Invalid option: -$OPTARG." ;;

    :) fatal "Option -$OPTARG requires an argument." ;;

  esac
done

debug "Reading options completed."

shift $(( OPTIND - 1 ))

# Assume all other arguments are filenames
checkpoint_list+=("$@")

if (( ${#checkpoint_list[*]} == 0 )) ; then
  warning "No checkpoint files to operate on."
  (( exit_status++ ))
else
  format_list "${checkpoint_list[@]}" || exit_status=$?
fi

message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

(( exit_status == 0 )) || fatal "There have been one or more errors."
#hlp   $scriptname is part of $softwarename $version ($versiondate) 
