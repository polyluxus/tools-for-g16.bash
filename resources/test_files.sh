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

#
# Test, whether we can access the given file/directory
#

is_file ()
{
    [[ -f $1 ]]
}

is_readable ()
{
    [[ -r $1 ]]
}

is_readable_file_or_exit ()
{
    is_file "$1"     || fatal "Specified file '$1' is no file or does not exist."
    is_readable "$1" || fatal "Specified file '$1' is not readable."
    echo "$1"
}

is_readable_file_and_warn ()
{
    is_file "$1"     || warning "Specified file '$1' is no file or does not exist."
    is_readable "$1" || warning "Specified file '$1' is not readable."
    echo "$1"
}

#
# Check if file exists and prevent overwriting
#

test_file_location ()
{
    local savesuffix=1 file_return="$1"
    debug "Checking file: $file_return"
    if ! is_file "$file_return" ; then
      echo "$file_return"
      debug "There is no file '$file_return'. Return 0."
      return 0
    else
      while is_file "${file_return}.${savesuffix}" ; do
        (( savesuffix++ ))
        debug "The file '${file_return}.${savesuffix}' exists."
      done
      debug "File '$file_return' exists."
      echo "${file_return}.${savesuffix}"
        debug "There is no file '${file_return}.${savesuffix}'. Return 1."
      return 1
    fi
}

backup_file ()
{
    local move_message move_source="$1" move_target="$2"
    debug "Will attempt: mv -v -- $move_source $move_target"
    move_message="$( mv -v -- "$move_source" "$move_target" 2>&1 )" || fatal "Backup went wrong. $move_message"
    message "File will be backed up."
    message "$move_message"
}

backup_if_exists ()
{
    local move_target
    move_target=$(test_file_location "$1") && return
    warning "File '$1' exists."
    backup_file "$1" "$move_target"
}

