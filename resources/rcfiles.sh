#!/bin/bash

# If this script is not sourced, return before executing anything
if (return 0 2>/dev/null) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  : #Everything is fine
else
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Get settings from configuration file
#

test_rc_file ()
{
  local test_runrc="$1"
  debug "Testing '$test_runrc' ..."
  if [[ -f "$test_runrc" && -r "$test_runrc" ]] ; then
    echo "$test_runrc"
    return 0
  else
    debug "... missing."
    return 1
  fi
}

get_rc ()
{
  local test_runrc_dir test_runrc_loc return_runrc_loc runrc_basename
  # The rc should have some similarity with the actual scriptname
  local runrc_basename="$scriptbasename" runrc_bundle="g16.tools"
  while [[ ! -z $1 ]] ; do
    test_runrc_dir="$1"
    shift
    if test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_basename}rc")" ; then
      return_runrc_loc="$test_runrc_loc" 
      debug "   (found) return_runrc_loc=$return_runrc_loc"
      continue
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_basename}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_bundle}rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_bundle}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    fi
  done
  debug "(returned) return_runrc_loc=$return_runrc_loc"
  echo "$return_runrc_loc"
}

