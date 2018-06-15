#!/bin/bash

#hlp   This is $scriptname!
#hlp
#hlp   It finds energy statements from Gaussian 16 calculations,
#hlp   or find energy statements from all G16 log files in the 
#hlp   working directory.
#hlp 
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp
#hlp   VERSION    :   $version
#hlp   DATE       :   $versiondate
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

#
# Specific functions for this script only
#

# Maybe worth putting in lib
match_output_suffix ()
{
  local   allowed_input_suffix=(com in  inp gjf COM IN  INP GJF)
  local matching_output_suffix=(log out log log LOG OUT LOG LOG)
  local choices=${#allowed_input_suffix[*]} count
  local test_suffix="$1" return_suffix
  debug "test_suffix=$test_suffix; choices=$choices"
  
  # Assign matching outputfile
  for (( count=0 ; count < choices ; count++ )) ; do
    debug "count=$count"
    if [[ "$test_suffix" == "${matching_output_suffix[$count]}" ]]; then
      return_suffix="$extract_suffix"
      debug "Recognised output suffix: $return_suffix."
      break
    elif [[ "$test_suffix" == "${allowed_input_suffix[$count]}" ]]; then
      return_suffix="${matching_output_suffix[$count]}"
      debug "Matched output suffix: $return_suffix."
      break
    else
      debug "No match for $test_suffix; $count; ${allowed_input_suffix[$count]}; ${matching_output_suffix[$count]}"
    fi
  done

  [[ -z $return_suffix ]] && return 1

  echo "$return_suffix"
}

match_output_file ()
{
  # Check what was supplied and if it is read/writeable
  # Returns a filename
  local extract_suffix return_suffix basename
  local testfile="$1" return_file
  debug "Validating: $testfile"

  basename="${testfile%.*}"
  extract_suffix="${testfile##*.}"
  debug "basename=$basename; extract_suffix=$extract_suffix"

  if return_suffix=$(match_output_suffix "$extract_suffix") ; then
    return_file="$basename.$return_suffix"
  else
    return 1
  fi

  [[ -r $return_file ]] || return 1

  echo "$return_file"    
}


find_energy ()
{
    local logfile="$1"
    # Initiate variables necessary for parsing output
    local readline pattern functional energy cycles
    # Find match from the end of the file 
    # Ref: http://unix.stackexchange.com/q/112159/160000
    # This is the slowest part. 
    # If the calulation is a single point with a properties block it might 
    # perform slower than $(grep -m1 'SCF Done'c $logfile | tail -n 1).
    readline=$(tac "$logfile" | grep -m1 'SCF Done')
    # Gaussian output has following format, trap important information:
    # Method, Energy, Cycles
    # Example taken from BP86/cc-pVTZ for water (H2O): 
    #  SCF Done:  E(RB-P86) =  -76.4006006969     A.U. after   10 cycles
    pattern="(E\\(.+\\)) = (.+) [aA]\\.[uU]\\.[^0-9]+([0-9]+) cycles"
    if [[ $readline =~ $pattern ]]
    then 
      functional="${BASH_REMATCH[1]}"
      energy="${BASH_REMATCH[2]}"
      cycles="${BASH_REMATCH[3]}"

      # Print the line, format it for table like structure
      printf '%-25s %-15s = %20s ( %6s )\n' "${logfile%.*}" "$functional" "$energy" "$cycles"
    else
      printf '%-25s No energy statement found.\n' "${logfile%.*}"
    fi
}

process_one_file ()
{
  # run only for one file at the time
  local testfile="$1" logfile
  if logfile="$(match_output_file "$testfile")" ; then
    find_energy "$logfile"
  else
    printf '%-25s No output file found.\n' "${testfile%.*}"
  fi
}

process_directory ()
{
  # Find all files in a directory
  local suffix="$1" process_file
  printf '%-25s %s\n' "Summary for " "${PWD#\/*\/*\/}" 
  printf '%-25s %s\n\n' "Created " "$(date +"%Y/%m/%d %k:%M:%S")"
  # Print a header
  printf '%-25s %-15s   %20s ( %6s )\n' "Command file" "Functional" "Energy / Hartree" "cycles"
  for process_file in *."$suffix" ; do
    [[ "$process_file" == "*.$suffix" ]] && fatal "No files found matching '$process_file'."
    process_one_file "$process_file"
  done
}

#
# Begin main script
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

# Who are we and where are we?
scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
debug "Script is called '$scriptname'"
# remove scripting ending (if present)
scriptbasename=${scriptname%.sh} 
debug "Base name of the script is '$scriptbasename'"
scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
debug "Script is located in '$scriptpath'"

# Import default variables
#shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/default_variables.sh
source $scriptpath/resources/default_variables.sh

# Set more default variables
# exit_status=0 #(Not used.)
stay_quiet=0
process_input_files="true"

# Import other functions
#shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/messaging.sh
source $scriptpath/resources/messaging.sh
#shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/rcfiles.sh
source $scriptpath/resources/rcfiles.sh
#shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/test_files.sh
source $scriptpath/resources/test_files.sh

# Get options
# Initialise options
OPTIND="1"

while getopts :hqi:o: options ; do
  #hlp   USAGE      :   $scriptname [options] <filenames>
  #hlp
  #hlp   If no filenames are specified, the script looks for all '*.com'
  #hlp   files and assumes there is a matching '*.log' file.
  #hlp
  #hlp   OPTIONS:
  case $options in
    #hlp     -h        Prints this help text
    #hlp
    h) helpme ;; 

    #hlp     -q        Suppress messages, warnings, and errors
    #hlp               (May be specified multiple times.)
    #hlp
    q) (( stay_quiet++ )) ;; 

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

    #hlp More options in preparation.
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
  (( $# > 1 )) && printf '%-25s %-15s   %20s ( %6s )\n' "Command file" "Functional" "Energy / Hartree" "cycles"
  for inputfile in "$@"; do
    process_one_file "$inputfile"
  done
fi

message "Created with '$script_invocation_spell'."
#hlp (Martin; $version; $versiondate.)
message "$scriptname is part of $softwarename $version ($versiondate)"
