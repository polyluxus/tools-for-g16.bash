#!/bin/bash

#hlp This script is a utility meant to configure the 
#hlp predefined route sections for the scripts of tools-for-g16.bash
#hlp

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
    # We are in another subdirectory
    scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "current installdirectory")"
    # move one up
    debug "Script is located in '$scriptpath'"
    resourcespath="$scriptpath/../resources"
    
    if [[ -d "$resourcespath" ]] ; then
      debug "Found library in '$resourcespath'."
    else
      (( error_count++ ))
    fi
    
    # Import default variables
    #shellcheck source=../resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Import other functions
    #shellcheck source=../resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=../resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=../resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=../resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=../resources/validate_numbers.sh
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
# Read config files
#

get_configuration_from_file ()
{
  # Check for settings in four default locations (increasing priority):
  #   install path of the script, user's home directory, 'config' in user's home directory, current directory
  g16_tools_path=$(get_absolute_dirname "$scriptpath/../g16.tools.rc")
  local g16_tools_rc_searchlocations
  g16_tools_rc_searchlocations=( "$g16_tools_path" "$HOME" "$HOME/.config" "$PWD" )
  g16_tools_rc_loc="$( get_rc "${g16_tools_rc_searchlocations[@]}" )"
  debug "g16_tools_rc_loc=$g16_tools_rc_loc"
  
  # Load custom settings from the rc
  
  if [[ -n $g16_tools_rc_loc ]] ; then
    #shellcheck source=../g16.tools.rc 
    . "$g16_tools_rc_loc"
    message "Configuration file '${g16_tools_rc_loc/*$HOME/<HOME>}' applied."
  fi
}
#
# Specific functions for this script only
#

write_to_file ()
{
  echo "$*" >&9
}

read_index ()
{
  debug "Reading integer."
  local readvar
  until [[ $readvar =~ ^[[:space:]]*([Dd]?[[:digit:]]+[Dd]?|[Qq]|[Ss])[[:space:]]*$ ]] ; do
    message "Which route section would you like to edit?"
    message "To create a new route section pick an unused number."
    message "To delete a route section suffix/append 'd' to its index number."
    message "Enter 's' save the manipulated data to '$output_file'."
    message "Please enter an integer value or 'q' to quit."
    [[ -n $custom_message ]] && message "$custom_message"
    echo -n "ANSWER  : " >&3
    read -r readvar
  done
  debug "Whole match is |${BASH_REMATCH[0]}|; Cleaned part is |${BASH_REMATCH[1]}|"
  readvar="${BASH_REMATCH[1]}"
  debug "readvar=$readvar"
  echo "$readvar"
}

list_route_sections ()
{
  local array_index=0
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
    [[ -z ${g16_route_section_predefined_comment[$array_index]} ]] && g16_route_section_predefined_comment[$array_index]="(n.a.)"
    while read -r printvar || [[ -n "$printvar" ]] ; do
      printf '%3d(cmt.) : %-80s\n' "$array_index" "${printvar:-no comment available}"
    done <<< "$( fold -w80 -s <<< "${g16_route_section_predefined_comment[$array_index]}" )"
  done
}

edit_single_route ()
{
  echo "This feature is not yet fully implemented."
#  sleep 1
  local editor="${EDITOR:-vim}"
  debug "Editor: $editor"
  local read_route_content="$1"
  debug "Processing route: $read_route_content"
  local read_route_comment="$2"
  debug "Processing comment: $read_route_comment"
  local tmpfile_route printvar
  tmpfile_route="$( mktemp --tmpdir )"
  debug "Created temporary file: $tmpfile_route"
  if command -v "$editor" > /dev/null ; then
    exec 9> "$tmpfile_route"
    write_to_file  "% This skript ($0) is used to configure the default route sections."
    write_to_file  "% Lines starting with per-cent (%) will be ignored silently."
    write_to_file  "% Lines starting with an exclamation mark (!) will be considered a comment."
    write_to_file  "% Every other line will be considered part of the route section."
    write_to_file  "% The route indicator may be omitted (and then defaults to #),"
    write_to_file  "% or explicitly specified to #N/#P/#T at the __beginning__ of the route section."
    write_to_file  "% Note that special characters may cause unforseen side-effects, as this is WIP."
    write_to_file  "$( fold -w80 -s <<< "${read_route_content:-#}" )"
    while read -r printvar || [[ -n "$printvar" ]] ; do
      [[ -z "$printvar" ]] && printvar="no comment"
      write_to_file "! $printvar"
    done <<< "$( fold -w78 -s <<< "$read_route_comment" )" 
    write_to_file  "% End of temporary file."
    exec 9>&-
    $editor "$tmpfile_route"
  else
    fatal "Command not found: $editor" 
  fi
  local line pattern 
  local return_route_startpattern return_route_content return_route_comment
  while read -r line || [[ -n "$line" ]] ; do
    debug "$line"
    [[ "$line" =~ ^[[:space:]]*% ]] && { debug "Explanation line." ; continue ; }
    [[ "$line" =~ ^[[:space:]]*![[:space:]]*(.*)$ ]] && { return_route_comment+="${BASH_REMATCH[1]} " ; debug "Comment line." ; continue ; }
    if [[ -z $return_route_content ]] ; then
      debug "No content in route yet."
      pattern="^[[:space:]]*(#[nNpPtT]?)"
      if [[ "$line" =~ $pattern ]] ; then 
        return_route_startpattern="${BASH_REMATCH[1]}" 
        return_route_content="${line##*$return_route_startpattern} " 
        return_route_content="${return_route_content##[[:space:]]} " 
        debug "Found start pattern: $return_route_startpattern"
        debug "Found route content: $return_route_content"
        continue 
      fi
    fi
    pattern="^[[:space:]]*#[^[:space]]*[[:space:]]*(.*)$"
    [[ "$line" =~ $pattern ]] && line="${BASH_REMATCH[1]}"
    return_route_content+="$line "
  done < "$tmpfile_route"
  debug "Comment: $return_route_comment"
  debug "Start pattern: $return_route_startpattern"
  debug "Route content: $return_route_content"
  edited_route="${return_route_startpattern:-#} $return_route_content ! $return_route_comment"
  debug "$( rm -v -- "$tmpfile_route" )"
}

### #TMP stuff for testing
### 
###   g16_route_section_predefined[0]="# PM6"
###   g16_route_section_predefined_comment[0]="semi-empirical method (default route)"
### #
###   g16_route_section_predefined[1]="#P B97D3/def2SVP/W06                            DenFit"
###   g16_route_section_predefined_comment[1]="pure DFT method with density-fitting, double zeta BS (default route)"
### #
###   g16_route_section_predefined[2]="#P B97D3/def2TZVPP/W06                          DenFit"
###   g16_route_section_predefined_comment[2]="pure DFT method with density-fitting, triple zeta BS (default route)"

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

# Need to define debug function if unknown (It should be unknown.)
if ! command -v debug > /dev/null ; then
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

# Get options
# Initialise options
OPTIND="1"

while getopts :hr:o:m: options ; do
  #hlp   Usage: $scriptname [options]
  #hlp
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -h        Prints this help text
    #hlp
    h) helpme ;; 

    #hlp     -r <ARG>  Raw mode. Do not load configuration files, use <ARG> as input. 
    #hlp
    r) raw_mode="true" ; raw_routes="$OPTARG" ;;

    #hlp     -o <ARG>  Specify output file for created route sections.
    #hlp
    o) output_file="$OPTARG" 
       ;;

    #hlp     -m <ARG>  Specify a custom message to include in the menu build.
    #hlp
    m) custom_message="$OPTARG" 
       ;;

    #hlp     --       Close reading options.
    #hlp
    # This is the standard closing argument for getopts, it needs no implemenation.

    \?) fatal "Invalid option: -$OPTARG." ;;

    :) fatal "Option -$OPTARG requires an argument." ;;

  esac
done

if [[ $raw_mode == "true" ]] ; then
  unset g16_route_section_predefined g16_route_section_predefined_comment
  #shellcheck disable=SC1090
  . "$raw_routes"
else
  get_configuration_from_file 
fi
output_file="${output_file:-$(mktemp)}"

list_route_sections 

while index=$( read_index ) ; do
  debug "Index chosen: $index"
  [[ "$index" == "q" || "$index" == "Q" ]] && exit 0
  if [[ "$index" == "s" || "$index" == "S" ]] ; then
    {
      array_index=0
      echo "# Following route sections created:"
      for array_index in "${!g16_route_section_predefined[@]}" ; do
        printf '  g16_route_section_predefined[%d]="%s"\n' "$array_index" "${g16_route_section_predefined[$array_index]}"
        printf '  g16_route_section_predefined_comment[%d]="%s"\n' "$array_index" "${g16_route_section_predefined_comment[$array_index]}"
      done
      debug "$( declare -p g16_route_section_predefined )"
      debug "$( declare -p g16_route_section_predefined_comment )"
      echo "# done"
    } > "$output_file"
    exit 0
  fi
  if [[ "$index" =~ [Dd]+ ]] ; then
    index="${index//[^[:digit:]]/}"
    unset "g16_route_section_predefined[$index]"
    unset "g16_route_section_predefined_comment[$index]"
  else
    edit_single_route "${g16_route_section_predefined[$index]}" "${g16_route_section_predefined_comment[$index]}" 
    g16_route_section_predefined[$index]="${edited_route%%!*}"
    if validate_g16_route "${g16_route_section_predefined[$index]}" ; then
      debug "Route has no syntax error."
      g16_route_section_predefined_comment[$index]="${edited_route#*!}"
    else
      sleep 2
      debug "Route has syntax error(s)."
      g16_route_section_predefined_comment[$index]='(WARNING: Syntax error detected.) '
      g16_route_section_predefined_comment[$index]+="${edited_route#*!}"
    fi
  fi
  list_route_sections
done

#hlp $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

