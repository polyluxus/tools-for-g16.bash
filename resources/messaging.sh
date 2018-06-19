#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Print logging information and warnings nicely.
# If there is an unrecoverable error: display a message and exit.
#

message ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      if (( stay_quiet <= 0 )) ; then
        echo "INFO   : " "$line" >&3
      else
        debug "(info   ) " "$line"
      fi
    done <<< "$*"
}

warning ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      if (( stay_quiet <= 1 )) ; then
        echo "WARNING: " "$line" >&2
      else
        debug "(warning) " "$line"
      fi
    done <<< "$*"
    return 1
}

fatal ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      if (( stay_quiet <= 2 )) ; then 
        echo "ERROR  : " "$line" >&2
      else
        debug "(error  ) " "$line"
      fi
    done <<< "$*"
    exit 1
}

debug ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      echo "DEBUG  : " "$line" >&4
    done <<< "$*"
}    

#
# Print some helping commands
# The lines are distributed throughout the script and grepped for
#

helpme ()
{
    local line
    local pattern="^[[:space:]]*#hlp[[:space:]]?(.*)?$"
    while read -r line; do
      [[ "$line" =~ $pattern ]] && eval "echo \"${BASH_REMATCH[1]}\""
    done < <(grep "#hlp" "$0")
    exit 0
}

# 
# Issue warning if options are ignored.
#

warn_additional_args ()
{
    while [[ ! -z $1 ]]; do
      warning "Specified option $1 will be ignored."
      shift
    done
}

