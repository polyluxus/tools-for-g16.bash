#!/bin/bash

# The following script gives default values to any of the scripts within the package.
# They can (or should) be set in the rc file, too.

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Generic details about these tools 
#
softwarename="tools-for-g16.bash"
version="0.0.9"
versiondate="2018-07-03"

#
# Standard commands for external software:
#
# Gaussian related options
#
# General path to the g16 directory (this should work on every system)
g16_installpath="/path/is/not/set"
# Define where scratch files shall be written to
g16_scratch="$TEMP"
# Define the overhead you'd like to give Gaussian in MB 
g16_overhead=2000
# The 2000 might be a very conservative guess, but additionally
# the memory will be scaled by (CPU + 1)/CPU (at least in the submit script).
# Checkpoint files should be saved by default
g16_checkpoint_save="true"
# If a modular software management is available, use it?
load_modules="true"
# For example: On the RWTH cluster Gaussian is loaded via a module system,
# the names (in correct order) of the modules:
g16_modules[0]="CHEMISTRY"
g16_modules[1]="gaussian/16.a03_bin"
# Options relating to producing a formatted checkpoint file
g16_formchk_cmd="wrapper.g16 formchk" # ( Current workaround )
g16_formchk_opts="-3"
# Options related to testing the route section
g16_testrt_cmd="wrapper.g16 testrt" # ( Current workaround )
# (There are no options for this utility.)

# Options related to use open babel
obabel_cmd="obabel"

#
# Default files and suffixes
#
g16_input_suffix="com"
g16_output_suffix="log"

#
# Default options for printing
#
values_separator=" " # (space separated values)
output_verbosity=0

#
# Default values for queueing system submission
#
# Select a queueing system (pbs-gen/bsub-rwth) # TODO: bsub-gen
request_qsys="pbs-gen"
# Walltime for remote execution, header line for the queueing system
requested_walltime="24:00:00"
# Specify a default value for the memory (MB)
requested_memory=512
# This corresponds to nthreads/NProcShared (etc)
requested_numCPU=4
# Maxdisk keyword value (MB), will be written to the G16 inputfile
# (limits disk space)
requested_maxdisk=10000
# Account to project (currently only for bsub-rwth)
bsub_project=default
# Calculations will be submitted to run (hold/keep)
requested_submit_status="run"

