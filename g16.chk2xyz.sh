#!/bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019-2020 Martin C Schwarzer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
###

#hlp   ${0##*/} is a script to format a Gaussian 16 checkpointfile
#hlp   via the formchk utility and then create Cartesian coordinates 
#hlp   in (simple) xmol format using Open Babel.
#hlp
#hlp   tools-for-g16.bash  Copyright (C) 2019  Martin C Schwarzer
#hlp   This program comes with ABSOLUTELY NO WARRANTY; this is free software, 
#hlp   and you are welcome to redistribute it under certain conditions; 
#hlp   please see the license file distributed alongside this repository,
#hlp   which is available when you type 'g16.tools-info.sh -L',
#hlp   or at <https://github.com/polyluxus/tools-for-g16.bash>.
#hlp
#hlp   Usage: $scriptname [option] [--] <checkpointfile(s)>
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
    local error_count tmplog line
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
    #shellcheck source=./resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0
    
    # Import other functions
    #shellcheck source=./resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/validate_numbers.sh
    source "$resourcespath/validate_numbers.sh" &> "$tmplog" || (( error_count++ ))

    if (( error_count > 0 )) ; then
      echo "ERROR: Unable to locate library functions. Check installation." >&2
      echo "ERROR: Expect functions in '$resourcespath'."
      debug "Errors caused by:"
      while read -r line || [[ -n "$line" ]] ; do
        debug "$line"
      done < "$tmplog"
      debug "$(rm -v -- "$tmplog")"
      exit 1
    else
      debug "$(rm -v -- "$tmplog")"
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
    local g16_output  obabel_output
    local -a g16_formchk_commandline
    debug "Global variables used: 'g16_wrapper_cmd=\"$g16_wrapper_cmd\"'"
    debug "Global variables used: 'g16_formchk_cmd=\"$g16_formchk_cmd\"' 'g16_formchk_opts=\"$g16_formchk_opts\"'"

    if [[ "${operation_write_mode}" =~ [Bb][Aa][Cc][Kk][Uu][Pp] ]] ; then
      debug "Backup mode will test files and prevent overwriting."
      backup_if_exists "$output_fchk"
      backup_if_exists "$output_xyz"
    elif [[ "${operation_write_mode}" =~ [Ss][Kk][Ii][Pp] ]] ; then
      debug "Skipping mode."
      [[ -e "$output_fchk" ]] && message "File '$output_fchk' exists, skipping." && return 0
      [[ -e "$output_xyz"  ]] && message "File '$output_xyz' exists, skipping." && return 0
    elif [[ "${operation_write_mode}" =~ [Ff][Oo][Rr][Cc][Ee] ]] ; then
      debug "Forced mode."
      [[ -e "$output_fchk" ]] && message "Forced mode. $( rm -v -- "$output_fchk" )"
      [[ -e "$output_xyz"  ]] && message "Forced mode. $( rm -v -- "$output_xyz" )"
    fi

    # Check whether the command is actually set
    if [[ -z $g16_formchk_cmd ]] ; then
      warning "Command to 'formchk' is unset, action cannot be performed."
      return 1
    fi
    # Check if a wrapper should be used
    if [[ -n $g16_wrapper_cmd ]] ; then
      command -v "$g16_wrapper_cmd" &> /dev/null || { warning "Wrapper command ($g16_wrapper_cmd) not found." ; return 1 ; }
      $g16_wrapper_cmd command -v "$g16_formchk_cmd" &> /dev/null || { warning "Wrapped formchk command ($g16_formchk_cmd) not found." ; return 1 ; }
      g16_formchk_commandline=( "$g16_wrapper_cmd" "$g16_formchk_cmd" )
      debug "Current command line: ${g16_formchk_commandline[*]}"
    else
      command -v "$g16_formchk_cmd" &> /dev/null || { warning "Gaussian formchk command ($g16_formchk_cmd) not found." ; return 1 ; }
      g16_formchk_commandline=( "$g16_formchk_cmd" )
      debug "Current command line: ${g16_formchk_commandline[*]}"
    fi
    
    # Run the programs
    [[ -z "$g16_formchk_opts" ]] || g16_formchk_commandline+=( "$g16_formchk_opts" )
    g16_formchk_commandline+=( "$use_input_chk" "$output_fchk" )
    debug "Current command line: ${g16_formchk_commandline[*]}"

    g16_output=$( ${g16_formchk_commandline[@]} 2>&1 ) || returncode="$?"
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
    
    command -v "$obabel_cmd" &> /dev/null || { warning "Open babel command ($obabel_cmd) not found." ; return 1 ; }
    obabel_output=$( $obabel_cmd -ifchk "$output_fchk" -oxyz -O"$output_xyz" 2>&1 ) || (( returncode+=$? ))
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

process_directory ()
{
  # Set the nullglob option to allow for empty globbing parameter
  shopt -s nullglob
  local checkpointfile
  for checkpointfile in ./*.chk ; do
    checkpoint_list+=( "$( get_absolute_location "$checkpointfile" )" )
    debug "Adding to list: '${checkpoint_list[-1]}"
  done
}

recurse_directories ()
{
  local directory_start="$1"
  local directory_to_process
  for directory_to_process in "$directory_start"/* ; do
    debug "Processing: $directory_to_process"
    if [[ -d "$directory_to_process" ]] ; then
      push_directory_to_stack "$directory_to_process" || fatal "Switching to '$directory_to_process' failed."
      recurse_directories "$PWD"
      pop_directory_from_stack -- || fatal "Popping directory from stack failed."
    fi
  done
  debug "Current location: $PWD"
  process_directory
}

#
# MAIN SCRIPT
#

# If this script is sourced, return before executing anything
if ( return 0 2>/dev/null ) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  debug "Script is sourced. Return now."
  return 0
fi

# Save how script was called
printf -v script_invocation_spell "'%s' " "${0/#$HOME/<HOME>}" "$@"

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

# Set default operation modus to single file

operation_file_mode=single
operation_write_mode=backup

get_scriptpath_and_source_files || exit 1

# Check whether we have the right numeric format (set it if not)
warn_and_set_locale

# Abort if neither options nor a file list is given
(( $# == 0 )) &&  fatal "No checkpointfile specified."

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
g16_tools_rc_searchlocations=( "$scriptpath" "$HOME" "$HOME/.config" "$PWD" )
g16_tools_rc_loc="$( get_rc "${g16_tools_rc_searchlocations[@]}" )"
debug "g16_tools_rc_loc=$g16_tools_rc_loc"

# Load custom settings from the rc

if [[ -n $g16_tools_rc_loc ]] ; then
  #shellcheck source=./g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '${g16_tools_rc_loc/*$HOME/<HOME>}' applied."
  if [[ "${configured_version}" =~ ^${version%.*} ]] ; then 
    debug "Config: $configured_version ($configured_versiondate); Current: $version ($versiondate)."
  else
    warning "Configured version was ${configured_version:-unset} (${configured_versiondate:-unset}),"
    warning "and probably needs an update to $version ($versiondate)."
  fi
else
  debug "No custom settings found."
fi

# Initialise options
debug "Initialising option index."
OPTIND="1"

while getopts :aABFSRPsh options ; do
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -a         Selects all checkpointfiles that are found in the current directory.
    #hlp                Create backup files in cases where it would overwrite the files.
    #hlp
    a) 
      debug "Executing for directory."
      operation_file_mode="all"
      # operation_write_mode="backup"
      debug "Setting modus to '${operation_file_mode}'."
      ;;
    #hlp     -A         Formats almost all checkpointfiles that are found in the current directory.
    #hlp                Skips files in cases where it would overwrite them.
    #hlp                This is synonymous with -aS.
    #hlp
    A)
      debug "Executing for directory. Skipping already formatted files."
      operation_file_mode="all"
      operation_write_mode="skip"
      debug "Setting modus to '${operation_file_mode}' and '${operation_write_mode}'."
      ;;
    #hlp     -B         Create backup files in cases where it would overwrite them. [Default]
    #hlp                Only the last option amongst -B/-F/-S will take affect.
    #hlp
    B) 
      operation_write_mode="backup"
      debug "Setting modus to '${operation_write_mode}'."
      ;;
    #hlp     -F         Forces files to be overwritten (actually they are removed before writing).
    #hlp                Only the last option amongst -B/-F/-S will take affect.
    #hlp
    F) 
      operation_write_mode="force"
      debug "Setting modus to '${operation_write_mode}'."
      ;;
    #hlp     -S         Skips files in cases where it would overwrite them.
    #hlp                Only the last option amongst -B/-F/-S will take affect.
    #hlp
    S) 
      operation_write_mode="skip"
      debug "Setting modus to '${operation_write_mode}'."
      ;;
    #hlp     -R         Recurse through directories.
    #hlp
    R)
      debug "Recursing through directories."
      operation_file_mode="recursive"
      debug "Setting modus to '${operation_file_mode}'."
      ;;
    #hlp     -P         Print a list of filename which would be processed (dry run).
    #hlp
    P)
      printonly="true"
      debug "Only printing filenames."
      ;;
    #hlp     -s         Suppress messages, warnings, and errors of this script
    #hlp                (May be specified multiple times.)
    #hlp
    s) 
      (( stay_quiet++ )) 
      ;; 
    #hlp     -h         Prints this help text
    #hlp
    h) 
      helpme 
      ;; 

    #hlp     --         Close reading options.
    # This is the standard closing argument for getopts, it needs no implemenation.

    \?) 
     fatal "Invalid option: -$OPTARG." 
     ;;

    :) 
     fatal "Option -$OPTARG requires an argument." 
     ;;

  esac
done

debug "Reading options completed."

shift $(( OPTIND - 1 ))

# needs work: vars etc
case "$operation_file_mode" in
  single)
    debug "Explicitly adding checkpoint files to process (file mode: $operation_file_mode)."
    # Assume all other arguments are filenames
    checkpoint_list+=("$@")
    debug "Processing: ${checkpoint_list[*]}"
    ;;
  all)
    debug "Executing for directory; looking for all checkpoint files."
    (( ${#checkpoint_list[*]} == 0 )) || warning "File list already contains ${#checkpoint_list[*]} elements, they will be unset."
    process_directory
    debug "Found: ${checkpoint_list[*]}"
    (( ${#checkpoint_list[*]} == 0 )) &&  warning "No checkpoint files found in this directory."
    warn_additional_args "$@"
    ;;
  recursive)
    debug "Recursing through directories (file mode: $operation_file_mode)."
    recurse_directories "$PWD"
    ;;
  *)
    fatal "Unrecognised operation mode: '$operation_file_mode'."
    ;;
esac

if (( ${#checkpoint_list[*]} == 0 )) ; then
  warning "No checkpoint files to operate on."
  (( exit_status++ ))
elif [[ "$printonly" == "true" ]] ; then
  printf '%s\n' "${checkpoint_list[@]}"
  exit_status=0
else
  format_list "${checkpoint_list[@]}" || exit_status=$?
fi

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

(( exit_status == 0 )) || fatal "There have been one or more errors."
