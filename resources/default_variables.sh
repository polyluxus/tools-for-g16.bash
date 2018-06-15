#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

# Generic details about these tools 
softwarename="tools-for-g16.bash"
version="0.0.7"
versiondate="2018-06-xx"


# Standard commands:
g16_formchk_cmd="wrapper.g16 formchk" # ( Current workaround )
g16_formchk_opts="-3"
obabel_cmd="obabel"

# Default files and suffixes
g16_input_suffix="com"
g16_output_suffix="log"

