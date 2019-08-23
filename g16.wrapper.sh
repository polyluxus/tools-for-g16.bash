#!/bin/bash
#
#hlp This is a wrapper script to set the Gaussian 16 environemt, 
#hlp so that available  utilities can be used interactively.
#hlp See http://gaussian.com/utils/ for more information.
#hlp Usage: $scriptname [option] [--] <commands>
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

# Create a scratch directory for temporary files
cleanup_scratch () {
  message "Looking for files with filesize zero and delete them in '$g16_scratch'."
  debug "$( find "$g16_scratch" -type f -size 0 -exec rm -v -- {} \; )"
  message "Deleting scratch '$g16_scratch' if empty."
  debug "$( find "$g16_scratch" -maxdepth 0 -empty -exec rmdir -v -- {} \; )"
  [[ -e "$g16_scratch" ]] && warning "Scratch directory ($g16_scratch) is not empty, please check whether you need the files."
}

make_scratch ()
{
  debug "Creating new scratch directory."
  local tempdir_pattern='^(|[Tt][Ee]?[Mm][Pp]([Dd][Ii][Rr])?|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$'
  debug "g16_scratch='$g16_scratch'; pattern: $tempdir_pattern"
  if [[ "$g16_scratch" =~ $tempdir_pattern ]] ; then
    debug "Pattern was found."
    #shellcheck disable=SC2016
    g16_scratch=$( mktemp --directory --tmpdir )
  else
    debug "Pattern was not found."
    g16_scratch=$( mktemp --directory --tmpdir="$g16_scratch" g16-interactive-XXXXXX )
  fi
  [[ -e "$g16_scratch" ]] || return 1
  trap cleanup_scratch EXIT SIGTERM
}

# How Gaussian is loaded
load_gaussian ()
{
  if [[ "$load_modules" =~ [Tt][Rr][Uu][Ee] ]] ; then
    (( ${#g16_modules[*]} == 0 )) && fatal "No modules to load."
    # assume that in the interactive session everything is set alright already
    module load ${g16_modules[*]} 
  else
    [[ -z "$g16_installpath" ]] && fatal "Gaussian path is unset."
    [[ -e "$g16_installpath/g16/bsd/g16.profile" ]] && fatal "Gaussian profile does not exist."
    # Gaussian needs the g16root variable
    g16root="$g16_installpath"
    export g16root
    #shellcheck disable=SC1090
    . "${g16root}"/g16/bsd/g16.profile
  fi
  make_scratch || fatal "Setting scratch failed."
  GAUSS_SCRDIR="$g16_scratch"
  message "Using scratch '$g16_scratch'."
  GAUSS_MEMDEF="${requested_memory}MB"
  GAUSS_MDEF="${requested_memory}MB"
  GAUSS_PDEF=$requested_numCPU
  debug "$(declare -p g16root GAUSS_SCRDIR GAUSS_MEMDEF GAUSS_MDEF GAUSS_PDEF)"
  export GAUSS_SCRDIR GAUSS_MEMDEF GAUSS_MDEF GAUSS_PDEF
}

#
# MAIN SCRIPT
#

# If this script is sourced, return before executing anything
if ( return 0 2> /dev/null ) ; then
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

# Warn if neither options nor a command is given
(( $# == 0 )) && warning "There is nothing to do."

# Check for settings in four default locations (increasing priority):
#   install path of the script, user's home directory, .config in user's home, current directory
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

while getopts :m:p:sh options ; do
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -m <ARG>   Define the total memory to be used in megabyte.
    #hlp                (Default: $requested_memory)
    #hlp
      m) 
         validate_integer "$OPTARG" "the memory"
         if (( OPTARG == 0 )) ; then
           fatal "Memory limit must not be zero."
         fi
         requested_memory="$OPTARG" 
         ;;

    #hlp     -p <ARG>   Define number of professors to be used. 
    #hlp                (Default: $requested_numCPU)
    #hlp
      p) 
         validate_integer "$OPTARG" "the number of threads"
         if (( OPTARG == 0 )) ; then
           fatal "Number of threads must not be zero."
         fi
         requested_numCPU="$OPTARG" 
         ;;

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

# Assume all other arguments are part of the wrapped command
g16_commandline=("$@")
debug "Processing: ${g16_commandline[*]}"

#Now load gaussian here
load_gaussian || fatal "Loading Gaussian failed."

"${g16_commandline[@]}" || exit_status=$?

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

(( exit_status == 0 )) || fatal "There have been one or more errors."
