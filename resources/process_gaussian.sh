#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

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
    local logfile="$1" logname
    logname=${logfile%.*}
    logname=${logname/\.\//}
    # Initiate variables necessary for parsing output
    local readline pattern functional energy cycles
    # Find match from the end of the file 
    # Ref: http://unix.stackexchange.com/q/112159/160000
    # This is the slowest part. 
    # If the calulation is a single point with a properties block it might 
    # perform slower than $(grep -m1 'SCF Done' $logfile | tail -n 1).
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
      printf '%-25s %-15s = %20s ( %6s )\n' "$logname" "$functional" "$energy" "$cycles"
    else
      printf '%-25s No energy statement found.\n' "${logfile%.*}"
      return 1
    fi
}




