#!/bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019 Martin C Schwarzer
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

# The following script gives default values to any of the scripts within the package.
# They can (or should) be set in the rc file, too.

# If this script is not sourced, return before executing anything
if (return 0 2>/dev/null) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  : #Everything is fine
else
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Generic details about these tools 
#
softwarename="tools-for-g16.bash"
version="0.3.1"
versiondate="2019-09-11"

#
# Standard commands for external software:
#
# Gaussian related options
#
# General path to the g16 directory (this should work on every system)
g16_installpath="/path/is/not/set"
# Define where scratch files shall be written to.
# As default we will write a 'mktemp' statement to the submitfile.
# To use this feature, values from TMP...tmp...tempdir...TEMPDIR, default, 0, (empty)
# are accepted settings; if the pattern is not matched, the value will be taken as a directory
g16_scratch="default"
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
g16_modules[1]="gaussian/16.b01_bin"
# Specify a path to a wrapper command loading the Gaussian environment, 
# this will be executed immediately before the utilities below
# g16_wrapper_cmd="wrapper.g16" # for example
# empty by default
g16_wrapper_cmd=""
# Options relating to producing a formatted checkpoint file
# should be found in PATH, an absolute path, or found via the wrapper above
g16_formchk_cmd="formchk"
g16_formchk_opts="-3"
# Options related to testing the route section
# should be found in PATH, an absolute path, or found via the wrapper above
g16_testrt_cmd="testrt" 
# (There are no options for this utility.)

# Options related to use open babel
obabel_cmd="obabel"

# Options related to the external use of NBO6
nbo6_interface=active
nbo6_installpath="/path/is/not/set/"

#
# Default files, suffixes, options for Gaussian 16
#
g16_input_suffix="com"
g16_output_suffix="log"
g16_route_section_predefined[0]="# PM6"
g16_route_section_predefined_comment[0]="semi-empirical method (default route)"
g16_route_section_predefined[1]="#P BP86/def2SVP   EmpiricalDispersion=GD3BJ"
g16_route_section_predefined_comment[1]="pure DFT method with DFT-D3 with Becke-Johnson damping, double zeta BS (default route)"
g16_route_section_predefined[2]="#P B97D3/def2SVP"
g16_route_section_predefined_comment[2]="pure DFT method with double zeta BS (default route)"
g16_route_section_default="# B97D3/def2SVP"

#
# Default options for printing
#
values_separator=" " # (space separated values)
output_verbosity=0

#
# Default values for queueing system submission
#
# Select a queueing system (pbs-gen, slurm-gen, slurm-rwth, bsub-rwth, bsub-gen)
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
qsys_project=default
# E-Mail address to send notifications to
user_email=default
# Activate/deactivate sending extra mail (this is a configuration file only option)
# ("1/yes/active" or "0/no/disabled")
xmail_interface="disabled"
# Provide the interface command (this can be any script/binary)
xmail_cmd="mail"
# Request a certain machine type
bsub_machinetype=default
# Calculations will be submitted to run (hold/keep)
requested_submit_status="run"

