#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
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
    debug "Will attempt: mv -v $move_source $move_target"
    move_message="$(mv -v "$move_source" "$move_target")" || fatal "Backup went wrong."
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

