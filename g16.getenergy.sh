#!/bin/bash

#hlp   It finds energy statements from Gaussian 16 calculations,
#hlp   or find energy statements from all G16 log files in the 
#hlp   working directory.
#hlp 
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp

# Related Review of original code:
# http://codereview.stackexchange.com/q/129854/92423
# Thanks to janos and 200_success

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
    # exit_status=0
    stay_quiet=0
    process_input_files="true"
    print_full_logname="false"
    # set default format for logfile format
    print_format_logname="%-25s"
    print_one_line="false"
    recurse_through_directories="false"
    header_printed="false"
    
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

print_headerline ()
{
  [[ "$header_printed" == "false" ]] || return 0 
  # shellcheck disable=SC2059
  printf "$print_format_logname %-15s   %20s ( %6s )\n" "Command file" "Functional" "Energy / Hartree" "cycles"
  header_printed="true"
}

process_one_file ()
{
  # run only for one file at the time
  local testfile="$1" logfile logname
  local readline returned_array
  local functional energy cycles
  debug "Tested file: ${testfile}."

  if logfile="$(match_output_file "$testfile")" ; then
    logname=${logfile%.*}
    logname=${logname/\.\//}
    (( ${#logname} > 25 )) && logname="${logname:0:10}*${logname:(-14)}"
    debug "Using: '$logname' for '$testfile'."
    # Could also be achived with getlines_g16_output_file but would be overkill
    readline=$(tac "$logfile" | grep -m1 'SCF Done')
    mapfile -t returned_array < <( find_energy "$readline" )
    debug "Array written, ${#returned_array[@]} elements"
    functional="${returned_array[0]}"
    energy="${returned_array[1]}"
    cycles="${returned_array[2]}"
    if [[ "$print_full_logname" == "true" ]] ; then
      # Overwrite format for logfile
      if [[ "$print_one_line" == "true" ]] ; then
        logname="$(get_absolute_location "$logfile")"
      else
        logname="$logfile"
      fi
    fi

    if (( ${#returned_array[@]} > 0 )) ; then
      # shellcheck disable=SC2059
      printf "$print_format_logname %-15s = %20s ( %6s )\\n" "$logname" "$functional" "$energy" "$cycles"
    else
      # shellcheck disable=SC2059
      printf "$print_format_logname No energy found.\\n" "$logname"
      return 1
    fi
  else
    logname=${testfile/\.\//}
    logname="${logname} (input)"
    if [[ "$print_full_logname" == "true" ]] ; then
      # Overwrite format for logfile
      if [[ "$print_one_line" == "true" ]] ; then
        logname="$(get_absolute_location "$testfile") (input)"
      else
        logname="$testfile (input)"
      fi
    fi
    # shellcheck disable=SC2059
    printf "$print_format_logname No output file found.\\n" "$logname"
    return 1
  fi
}

process_directory ()
{
  # Find all files in a directory
  local suffix="$1" returncode=0
  local -a file_list
  local testfile process_file 
  if [[ "$print_one_line" == "false" ]] ; then
    # shellcheck disable=SC2059
    printf "$print_format_logname %s\n" "Summary for " "${PWD#*$USER\/}" 
    # shellcheck disable=SC2059
    printf "$print_format_logname %s\n" "Created " "$(date +"%Y/%m/%d %k:%M:%S")"
  fi
  # Print a header
  print_headerline
  for testfile in ./*."$suffix" ; do
    [[ -e $testfile ]] || continue
    file_list+=( "$testfile" )
  done
  if (( ${#file_list[*]} == 0 )) ; then
    if [[ "$print_one_line" == "false" ]] ; then
      warning "No '*.$suffix' files found in this directory."
    else
      warning "No '*.$suffix' files found in directory '$PWD'."
    fi
    return 1
  else
    debug "Files found: ${#file_list[*]}"
  fi
  for process_file in "${file_list[@]}" ; do
    process_one_file "$process_file" || (( returncode++ ))
  done
  return $returncode
}

recurse_directories ()
{
  # Find all directories
  local returncode=0
  local suffix="$1"
  local directory_start="$2"
  local directory_process
  for directory_process in "$directory_start"/* ; do
    debug "Processing: $directory_process"
    if [[ -d "$directory_process" ]] ; then 
      debug "Directory found: $directory_process"
      push_directory_to_stack "$directory_process" || fatal "Switching to '$directory_process' failed."
      recurse_directories "$suffix" "$PWD"
      pop_directory_from_stack -- || fatal "Popping directory from stack failed."
    fi
  done
  if [[ "$print_one_line" == "false" ]] ; then
    # Always print a header in not one line mode
    header_printed="false"
  else
    # Only print a single header
    print_headerline
  fi
  debug "We are here: $PWD"
  process_directory "$suffix"
  [[ "$print_one_line" == "false" ]] && printf '\n'
}

#
# Begin main script
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

# Get options
# Initialise options
OPTIND="1"

while getopts :hsRL1i:o: options ; do
  #hlp   Usage: $scriptname [options] <filenames>
  #hlp
  #hlp   If no filenames are specified, the script looks for all '*.com'
  #hlp   files and assumes there is a matching '*.log' file.
  #hlp
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -h        Prints this help text.
    #hlp
    h) helpme ;; 

    #hlp     -s        Suppress messages, warnings, and errors.
    #hlp               (May be specified multiple times.)
    #hlp
    s) (( stay_quiet++ )) ;; 

    #hlp     -R        Recurse through directories.
    #hlp
    R) recurse_through_directories="true" ;;

    #hlp     -L        Print the full name and path (relative to the current pwd) of the logfile.
    #hlp               In combination with '-1', it will print the absolute path to the file.
    #hlp
    L) print_full_logname="true" ;;

    #hlp     -1        (in words: one) Print only one line per file.
    #hlp
    1) print_one_line="true" ;;

    #hlp     -i <ARG>  Specify input suffix if processing a directory.
    #hlp               (Will look for input files with given suffix and
    #hlp                automatically match suitable output file suffix.)
    #hlp
    i) g16_input_suffix="$OPTARG"
       process_input_files="true"
       ;;

    #hlp     -o <ARG>  Specify output suffix if processing a directory.
    #hlp
    o) g16_output_suffix="$OPTARG" 
       process_input_files="false"
       ;;

    #hlp     --       Close reading options.
    # This is the standard closing argument for getopts, it needs no implemenation.

   \?) fatal "Invalid option: -$OPTARG." ;;

    :) fatal "Option -$OPTARG requires an argument." ;;

    #hlp

  esac
done

shift $(( OPTIND - 1 ))

if [[ "$print_full_logname" == "true" ]] ; then
  # Overwrite format for logfile
  if [[ "$print_one_line" == "true" ]] ; then
    print_format_logname="%s "
  else
    print_format_logname="%s:\\n  "
  fi
fi

if (( $# == 0 )) ; then
  if [[ $process_input_files =~ [Tt][Rr][Uu][Ee] ]] ; then
    debug "Processing inputfiles with suffix '$g16_input_suffix'."
    use_g16_suffix="$g16_input_suffix" 
  else
    if use_g16_output_suffix=$(match_output_suffix "$g16_output_suffix") ; then
      debug "Recognised output suffix '$use_g16_output_suffix'."
    else
      fatal "Unrecognised output suffix '$g16_output_suffix'."
    fi
    use_g16_suffix="$use_g16_output_suffix"
  fi
  if [[ "$recurse_through_directories" =~ [Tt][Rr][Uu][Ee] ]] ; then
    debug "Recursing through directories."
    recurse_directories "$use_g16_suffix" "$PWD"
  else
    process_directory "$use_g16_suffix"
  fi
else
  # Print a header if more than one file specified
  if (( $# > 1 )) ; then 
    print_headerline
  fi
  for inputfile in "$@"; do
    process_one_file "$inputfile"
  done
fi

message "Created with $script_invocation_spell."
message "Created $(date +"%Y/%m/%d %k:%M:%S")."
message "$scriptname is part of $softwarename $version ($versiondate)"
#hlp   $scriptname is part of $softwarename $version ($versiondate) 
