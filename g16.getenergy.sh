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
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    # exit_status=0
    stay_quiet=0
    process_input_files="true"
    print_full_logname="false"
    
    # Import other functions
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/validate_numbers.sh
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

process_one_file ()
{
  # run only for one file at the time
  local testfile="$1" logfile logname print_format_logname
  local readline returned_array
  local functional energy cycles
  debug "Tested file: ${testfile}."
  # set default format for logfile format
  print_format_logname="%-25s"

  if logfile="$(match_output_file "$testfile")" ; then
    logname=${logfile%.*}
    logname=${logname/\.\//}
    (( ${#logname} > 25 )) && logname="${logname:0:10}*${logname:(-14)}"
    debug "Using: '$logname' for '$filename'."
    # Could also be achived with getlines_g16_output_file but would be overkill
    readline=$(tac "$logfile" | grep -m1 'SCF Done')
    mapfile -t returned_array < <( find_energy "$readline" )
    debug "Array written, ${#returned_array[@]} elements"
    functional="${returned_array[0]}"
    energy="${returned_array[1]}"
    cycles="${returned_array[2]}"
    if [[ "$print_full_logname" == "true" ]] ; then
      # Overwrite format for logfile
      print_format_logname="%s:\\n  "
      logname="$logfile"
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
  printf '%-25s %s\n' "Summary for " "${PWD#\/*\/*\/}" 
  printf '%-25s %s\n\n' "Created " "$(date +"%Y/%m/%d %k:%M:%S")"
  # Print a header
  if [[ "$print_full_logname" == "true" ]] ; then
    printf '%s\n   %-15s   %20s ( %6s )\n' "Command/output file" "Functional" "Energy / Hartree" "cycles"
  else
    printf '%-25s %-15s   %20s ( %6s )\n' "Command/output file" "Functional" "Energy / Hartree" "cycles"
  fi
  for testfile in ./*."$suffix" ; do
    [[ -e $testfile ]] || continue
    file_list+=( "$testfile" )
  done
  if (( ${#file_list[*]} == 0 )) ; then
    warning "No output files found in this directory."
    return 1
  else
    debug "Files found: ${#file_list[*]}"
  fi
  for process_file in "${file_list[@]}" ; do
    process_one_file "$process_file" || (( returncode++ ))
  done
  return $returncode
}

#
# Begin main script
#

# If this script is sourced, return before executing anything
(( ${#BASH_SOURCE[*]} > 1 )) && return 0

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

while getopts :hsLi:o: options ; do
  #hlp   Usage: $scriptname [options] <filenames>
  #hlp
  #hlp   If no filenames are specified, the script looks for all '*.com'
  #hlp   files and assumes there is a matching '*.log' file.
  #hlp
  #hlp   Options:
  #hlp
  case $options in
    #hlp     -h        Prints this help text
    #hlp
    h) helpme ;; 

    #hlp     -s        Suppress messages, warnings, and errors
    #hlp               (May be specified multiple times.)
    #hlp
    s) (( stay_quiet++ )) ;; 

    #hlp     -L        Print the full name and path (relative to pwd) of the logfile
    #hlp
    L) print_full_logname="true" ;;

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

  esac
done

shift $(( OPTIND - 1 ))

if (( $# == 0 )) ; then
  if [[ $process_input_files =~ [Tt][Rr][Uu][Ee] ]] ; then
    debug "Processing inputfiles with suffix '$g16_input_suffix'."
    process_directory "$g16_input_suffix" 
  else
    if use_g16_output_suffix=$(match_output_suffix "$g16_output_suffix") ; then
      debug "Recognised output suffix '$use_g16_output_suffix'."
    else
      fatal "Unrecognised output suffix '$g16_output_suffix'."
    fi
    process_directory "$use_g16_output_suffix"
  fi
else
  # Print a header if more than one file specified
  if (( $# > 1 )) ; then 
    if [[ "$print_full_logname" == "true" ]] ; then
      printf '%s\n   %-15s   %20s ( %6s )\n' "Command file" "Functional" "Energy / Hartree" "cycles"
    else
      printf '%-25s %-15s   %20s ( %6s )\n' "Command file" "Functional" "Energy / Hartree" "cycles"
    fi
  fi
  for inputfile in "$@"; do
    process_one_file "$inputfile"
  done
fi

message "Created with $script_invocation_spell."
message "$scriptname is part of $softwarename $version ($versiondate)"
#hlp   $scriptname is part of $softwarename $version ($versiondate) 
