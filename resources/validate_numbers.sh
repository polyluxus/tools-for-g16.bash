#! /bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Test if a given value is an integer
#

is_integer ()
{
    [[ $1 =~ ^[[:digit:]]+$ ]]
}

is_whole_number ()
{
    [[ $1 =~ ^[+-]?[[:digit:]]+$ ]]
}

is_float ()
{
    [[ $1 =~ ^[+-]?[[:digit:]]+\.[[:digit:]]+$ ]]
}

validate_integer () 
{
    if ! is_integer "$1"; then
        [ ! -z "$2" ] && fatal "Value for $2 ($1) is no positive integer."
          [ -z "$2" ] && fatal "Value \"$1\" is no positive integer."
    fi
}

validate_whole_number () 
{
    if ! is_whole_number "$1"; then
        [ ! -z "$2" ] && fatal "Value for $2 ($1) is no whole number."
          [ -z "$2" ] && fatal "Value \"$1\" is no whole number."
    fi
}

validate_float () 
{
    if ! is_float "$1"; then
        [ ! -z "$2" ] && fatal "Value for $2 ($1) is no floating point number."
          [ -z "$2" ] && fatal "Value \"$1\" is no floating point number."
    fi
}

# 
# Test whether a given walltime is in the correct format
#

format_duration_or_exit ()
{
    local check_duration="$1"
    # Split time in HH:MM:SS
    # Strips away anything up to and including the rightmost colon
    # strips nothing if no colon present
    # and tests if the value is numeric
    # this is assigned to seconds
    local trunc_duration_seconds=${check_duration##*:}
    validate_integer "$trunc_duration_seconds" "seconds"
    # If successful value is stored for later assembly
    #
    # Check if the value is given in seconds
    # "${check_duration%:*}" strips shortest match ":*" from back
    # If no colon is present, the strings are identical
    if [[ ! "$check_duration" == "${check_duration%:*}" ]]; then
        # Strip seconds and colon
        check_duration="${check_duration%:*}"
        # Strips away anything up to and including the rightmost colon
        # this is assigned as minutes
        # and tests if the value is numeric
        local trunc_duration_minutes=${check_duration##*:}
        validate_integer "$trunc_duration_minutes" "minutes"
        # If successful value is stored for later assembly
        #
        # Check if value was given as MM:SS same procedure as above
        if [[ ! "$check_duration" == "${check_duration%:*}" ]]; then
            #Strip minutes and colon
            check_duration="${check_duration%:*}"
            # # Strips away anything up to and including the rightmost colon
            # this is assigned as hours
            # and tests if the value is numeric
            local trunc_duration_hours=${check_duration##*:}
            validate_integer "$trunc_duration_hours" "hours"
            # Check if value was given as HH:MM:SS if not, then exit
            if [[ ! "$check_duration" == "${check_duration%:*}" ]]; then
                fatal "Unrecognised duration format."
            fi
        fi
    fi

    # Modify the duration to have the format HH:MM:SS
    # disregarding the format of the user input
    # keep only 0-59 seconds stored, let rest overflow to minutes
    local final_duration_seconds=$((trunc_duration_seconds % 60))
    # Add any multiple of 60 seconds to the minutes given as input
    trunc_duration_minutes=$((trunc_duration_minutes + trunc_duration_seconds / 60))
    # save as minutes what cannot overflow as hours
    local final_duration_minutes=$((trunc_duration_minutes % 60))
    # add any multiple of 60 minutes to the hours given as input
    local final_duration_hours=$((trunc_duration_hours + trunc_duration_minutes / 60))

    # Format string and print it
    printf "%d:%02d:%02d" "$final_duration_hours" "$final_duration_minutes" \
                          "$final_duration_seconds"
}


is_email ()
{
    # Simplified email matching
    # See: https://www.regular-expressions.info/email.html
    [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_email () 
{
    if ! is_email "$1"; then
        [ ! -z "$2" ] && fatal "Value for $2 ($1) is no email address."
          [ -z "$2" ] && fatal "Value '$1' is no email address."
    fi
}

