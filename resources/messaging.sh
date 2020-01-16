#!/bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019-2020 Martin C Schwarzer
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
# Please see the license file distributed alongside this repository,
# which is available when you type 'g16.tools-info.sh -L',
# or at <https://github.com/polyluxus/tools-for-g16.bash>.
#
###

# If this script is not sourced, return before executing anything
if (return 0 2>/dev/null) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  : #Everything is fine
else
  echo "This script is only meant to be sourced."
  exit 0
fi

# Set verbosity to 0 if undefined
stay_quiet=${stay_quiet:-0}

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

# If the used locale is not English or POSIX, the formatting of floating numbers of the 
# printf commands will produce an error
check_locale ()
{
  local -a locale_settings
  mapfile -t locale_settings < <(locale)
  debug "Current locale settings:"
  debug "$( fold -w80 -s <<< "$( printf '%s; ' "${locale_settings[@]}"; printf '\n' )" )"

  local exit_status=0
  debug "Testing LANG='$LANG' and LC_NUMERIC='$LC_NUMERIC'."
  [[ "$LANG" =~ ^en_US.(UTF-8|utf8)$ || -z $LANG ]] || exit_status=1
  [[ "$LC_NUMERIC" =~ ^(en_US.(UTF-8|utf8)|POSIX)$ || -z $LC_NUMERIC ]] || exit_status=1
  debug "Returning with $exit_status"
  return $exit_status
}

warn_and_set_locale ()
{
  if ! check_locale ; then
    warning "Formatting might not properly work for current locale."
    warning "Setting locale POSIX compliant."
    # [Temporarily change language for terminal messages/warnings/errors](https://askubuntu.com/a/844455/220129)
    unset LANG LANGUAGE LC_ALL LC_NUMERIC
    export LC_ALL=C 
    local -a locale_settings
    mapfile -t locale_settings < <(locale)
    debug "New locale settings:"
    debug "$( fold -w80 -s <<< "$( printf '%s; ' "${locale_settings[@]}"; printf '\n' )" )"
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

#
# Redefinitions of command functions
#

push_directory_to_stack ()
{
  local tmplog line returncode=0
  tmplog=$(mktemp --tmpdir tmplog.XXXXXXXX)
  debug "Created temporary log file: $tmplog"
  command pushd "$@" &> "$tmplog" || returncode="$?"
  while read -r line || [[ -n "$line" ]] ; do
    debug "(pushd) $line"
  done < "$tmplog"
  debug "$(rm -v -- "$tmplog")"
  return $returncode
}

pop_directory_from_stack ()
{
  local tmplog line returncode=0
  tmplog=$(mktemp --tmpdir tmplog.XXXXXXXX)
  debug "Created temporary log file: $tmplog"
  command popd "$@" > "$tmplog" || returncode="$?"
  while read -r line || [[ -n "$line" ]] ; do
    debug "(popd) $line"
  done < "$tmplog"
  debug "$(rm -v -- "$tmplog")"
  return $returncode
}

