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
    local line exit_status=0
    local pattern="^[[:space:]]*([^:[:space:]]+)[[:space:]]*:[[:space:]]*(.+)$"
    local external_identifier external_message
    while read -r line || [[ -n "$line" ]] ; do
      if [[ $line =~ $pattern ]] ; then
        external_identifier="${BASH_REMATCH[1]}"
        debug "external_identifier='$external_identifier'"
        external_message="${BASH_REMATCH[2]}"
        debug "external_message='$external_message'"
        case "$external_identifier" in
          [Ii][Nn][Ff][Oo])
            line="(External) $external_message"
            ;;
          [Ww][Aa][Rr][Nn][Ii][Nn][Gg])
            warning "(External) $external_message" 
            exit_status=$?
            continue
            ;;
          [Ee][Rr][Rr][Oo][Rr])
            fatal "(External) $external_message"
            exit_status=$?
            continue
            ;;
          *)
            line="(External $external_identifier) $external_message"
            ;;
        esac
      fi
      if (( stay_quiet <= 0 )) ; then
        echo "INFO    : $line" >&3
      else
        debug "(info)     $line"
      fi
    done <<< "$*"
    return $exit_status
}

warning ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      if (( stay_quiet <= 1 )) ; then
        echo "WARNING : $line" >&2
      else
        debug "(warning)  $line"
      fi
    done <<< "$*"
    return 1
}

fatal ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      if (( stay_quiet <= 2 )) ; then 
        echo "ERROR   : $line" >&2
      else
        debug "(error)    $line"
      fi
    done <<< "$*"
    exit 1
}

debug ()
{
    local line
    while read -r line || [[ -n "$line" ]] ; do
      echo "DEBUG   : (${FUNCNAME[1]}) $line" >&4
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

# 
# Issue warning if locale is wrong
#

# If the used locale is not English, the formatting of floating numbers of the 
# printf commands will produce an error
warn_and_set_locale ()
{
    if [[ "$LANG" =~ ^en_US.(UTF-8|utf8)$ ]]; then 
      debug "Locale is '$LANG'"
    else
      warning "Formatting might not properly work for '$LANG'."
      warning "Setting locale for this script to 'en_US.UTF-8'."
      set -x
        export LC_NUMERIC="en_US.UTF-8"
      set +x
    fi
}

#
# Print an array from a declare string
#

print_declared_array ()
{
    local parseline="$1"
    debug "Input: $parseline"
    local found_match
    local pattern="(\\[([0-9]+[0-9]*)\\]=\"([^\"]*)\")(.*)"
    while [[ "$parseline" =~ $pattern ]] ; do
      found_match="${BASH_REMATCH[1]}"
      debug "Matched: $found_match"
      printf '%5d : %s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
      parseline="${BASH_REMATCH[4]}"
      debug "parseline=$parseline"
      sleep 1
    done

    debug "$parseline"
}
