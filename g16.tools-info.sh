#!/bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019 Martin C Schwarzer
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

#
#hlp   ${0##*/} is a script to print information related to the repository
#hlp
#hlp   tools-for-g16.bash  Copyright (C) 2019  Martin C Schwarzer
#hlp   This program comes with ABSOLUTELY NO WARRANTY; this is free software, 
#hlp   and you are welcome to redistribute it under certain conditions; 
#hlp   please see the license file distributed alongside this repository,
#hlp   which is available when you type 'g16.tools-info.sh -L',
#hlp   or at <https://github.com/polyluxus/tools-for-g16.bash>.
#hlp
#hlp   Usage: $scriptname [option] 
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

print_license ()
{
  [[ -r "$scriptpath/LICENSE" ]] || fatal "No license file found. Your copy of the repository might be corrupted."
  if command -v less &> /dev/null ; then
    less "$scriptpath/LICENSE"
  else
    cat "$scriptpath/LICENSE"
  fi
}

print_settings ()
{
  cat <<-EOF
  g16_installpath=             ${g16_installpath:-<undefined>}
  g16_scratch=                 ${g16_scratch:-<undefined>}
  g16_overhead=                ${g16_overhead:-<undefined>}
  g16_checkpoint_save=         ${g16_checkpoint_save:-<undefined>}
  load_modules=                ${load_modules:-<undefined>}
  g16_wrapper_cmd=             ${g16_wrapper_cmd:-<undefined>}
  g16_testrt_cmd=              ${g16_testrt_cmd:-<undefined>}
  g16_formchk_cmd=             ${g16_formchk_cmd:-<undefined>}
  g16_formchk_opts=            ${g16_formchk_opts:-<undefined>}
  obabel_cmd=                  ${obabel_cmd:-<undefined>}
  g16_input_suffix=            ${g16_input_suffix:-<undefined>}
  g16_output_suffix=           ${g16_output_suffix:-<undefined>}
  stay_quiet=                  ${stay_quiet:-<undefined>}
  output_verbosity=            ${output_verbosity:-<undefined>}
  values_delimiter=            ${values_delimiter:-<undefined>}
  request_qsys=                ${request_qsys:-<undefined>}
  qsys_project=                ${qsys_project:-<undefined>}
  user_email=                  ${user_email:-<undefined>}
  bsub_machinetype=            ${bsub_machinetype:-<undefined>}
  qsys_email=                  ${qsys_email:-<undefined>}
  xmail_interface=             ${xmail_interface:-<undefined>}
  xmail_cmd=                   ${xmail_cmd:-<undefined>}
  requested_walltime=          ${requested_walltime:-<undefined>}
  requested_memory=            ${requested_memory:-<undefined>}
  requested_numCPU=            ${requested_numCPU:-<undefined>}
  requested_maxdisk=           ${requested_maxdisk:-<undefined>}
  requested_submit_status=     ${requested_submit_status:-<undefined>}
  g16_route_section_default=   ${g16_route_section_default:-<undefined>}
  Predefined route sections:
	EOF
  for array_index in "${!g16_route_section_predefined[@]}" ; do
    (( array_index > 0 )) && printf '\n'
    printf '%3d       : ' "$array_index" 
    local printvar printline=0
    while read -r printvar || [[ -n "$printvar" ]] ; do
      if (( printline == 0 )) ; then
        printf '%-80s\n' "$printvar"
      else
        printf '            %-80s\n' "$printvar"
      fi
      (( printline++ ))
    done <<< "$( fold -w80 -s <<< "${g16_route_section_predefined[$array_index]}" )"
    unset printvar 
    while read -r printvar || [[ -n "$printvar" ]] ; do
      [[ -z "$printvar" ]] && printvar="no comment"
      printf '%3d(cmt.) : %-80s\n' "$array_index" "$printvar"
    done <<< "$( fold -w80 -s <<< "${g16_route_section_predefined_comment[$array_index]}" )"
  done
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

get_scriptpath_and_source_files || exit 1

# Check whether we have the right numeric format (set it if not)
warn_and_set_locale

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

while getopts :PLh options ; do
  #hlp   Options:
  #hlp
  case $options in
    P)
      #hlp     -P         Prints all settings.
      #hlp
      if command -v less &> /dev/null ; then
        print_settings | less
      else
        print_settings
      fi
      ;;
    L)
      #hlp     -L         Show the license.
      #hlp
      print_license
      ;;
    h) 
      #hlp     -h         Prints this help text
      #hlp
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

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

(( exit_status == 0 )) || fatal "There have been one or more errors."
