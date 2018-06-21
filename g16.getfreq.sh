#!/bin/bash

#hlp This tool creates a summary for a single (or more) frequency calculation(s)
#hlp of the quantum chemical software suite Gaussian16.
#hlp It will, however, not fail if it is not one. 
#hlp It looks for a defined set of keywords and writes them to the screen.
#hlp
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp
#hlp   VERSION    :   $version
#hlp   DATE       :   $versiondate
#hlp
#hlp   USAGE      :   $scriptname [options] [IPUT_FILE]
#hlp

# An old version of this script was reviewed:
# http://codereview.stackexchange.com/q/131666/92423
# 

#
# Generic functions to find the scripts 
# (Copy of ./resources/locations.sh)
#
# Let's know where the script is and how it is actually called
#

get_absolute_location ()
{
    # Resolves the absolute location of parameter and returns it
    # Taken from https://stackoverflow.com/a/246128/3180795
    local resolve_file="$1" description="$2" 
    local link_target directory_name filename resolve_dir_name 
    debug "Getting directory for '$resolve_file'."
    #  resolve $resolve_file until it is no longer a symlink
    while [[ -h "$resolve_file" ]]; do 
      link_target="$(readlink "$resolve_file")"
      if [[ $link_target == /* ]]; then
        debug "File '$resolve_file' is an absolute symlink to '$link_target'"
        resolve_file="$link_target"
      else
        directory_name="$(dirname "$resolve_file")" 
        debug "File '$resolve_file' is a relative symlink to '$link_target' (relative to '$directory_name')"
        #  If $resolve_file was a relative symlink, we need to resolve 
        #+ it relative to the path where the symlink file was located
        resolve_file="$directory_name/$link_target"
      fi
    done
    debug "File is '$resolve_file'" 
    filename="$(basename "$resolve_file")"
    debug "File name is '$filename'"
    resolve_dir_name="$(dirname "$resolve_file")"
    directory_name="$(cd -P "$(dirname "$resolve_file")" && pwd)"
    if [[ "$directory_name" != "$resolve_dir_name" ]]; then
      debug "$description '$directory_name' resolves to '$directory_name'."
    fi
    debug "$description is '$directory_name'"
    if [[ -z $directory_name ]] ; then
      directory_name="."
    fi
    echo "$directory_name/$filename"
}

get_absolute_filename ()
{
    # Returns only the filename
    local resolve_file="$1" description="$2" return_filename
    return_filename=$(get_absolute_location "$resolve_file" "$description")
    return_filename=${return_filename##*/}
    echo "$return_filename"
}

get_absolute_dirname ()
{
    # Returns only the directory
    local resolve_file="$1" description="$2" return_dirname
    return_dirname=$(get_absolute_location "$resolve_file" "$description")
    return_dirname=${return_dirname%/*}
    echo "$return_dirname"
}

get_scriptpath_and_source_files ()
{
    local error_count tmplog line tmpmsg
    tmplog=$(mktemp tmp.XXXXXXXX) 
    # Who are we and where are we?
    scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
    debug "Script is called '$scriptname'"
    # remove scripting ending (if present)
    scriptbasename=${scriptname%.sh} 
    debug "Base name of the script is '$scriptbasename'"
    scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
    debug "Script is located in '$scriptpath'"
    resourcespath="$scriptpath/resources"
    
    if [[ -d "$resourcespath" ]] ; then
      debug "Found library in '$resourcespath'."
    else
      (( error_count++ ))
    fi
    
    # Import default variables
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0

    # Ensure that in/outputfile variables are empty
    unset inputfile
    unset outputfile
    
    # Import other functions
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-g16.bash/resources/validate_numbers.sh
    source "$resourcespath/validate_numbers.sh" &> "$tmplog" || (( error_count++ ))

    if (( error_count > 0 )) ; then
      echo "ERROR: Unable to locate library functions. Check installation." >&2
      echo "ERROR: Expect functions in '$resourcespath'."
      debug "Errors caused by:"
      while read -r line || [[ -n "$line" ]] ; do
        debug "$line"
      done < "$tmplog"
      tmpmsg=$(rm -v "$tmplog")
      debug "$tmpmsg"
      exit 1
    else
      tmpmsg=$(rm -v "$tmplog")
      debug "$tmpmsg"
    fi
}

#
# Specific functions for this script only
#


process_one_file ()
{
  # run only for one file at the time
  local testfile="$1" printlevel="$2" logfile logname
  local readline returned_array
  local functional energy cycles
  local temperature pressure zero_point_corr
  local thermal_corr_energy thermal_corr_enthalpy
  local thermal_corr_gibbs entropy_tot heatcap_tot
  if logfile="$(match_output_file "$testfile")" ; then
    logname=${logfile%.*}
    logname=${logname/\.\//}
    (( ${#logname} > 25 )) && logname="${logname:0:10}*${logname:(-14)}"

    if (( printlevel > 2 )) ; then
      extracted_route=$(getlines_route_g16_output_file "$logfile")
      echo "The following route was extracted (first one encountered):"
      fold -w80 -c -s <<< "$extracted_route"
      echo "----------"
    fi

    debug "$(getlines_energy_g16_output_file "$logfile")"

    while read -r readline || [[ -n "$readline" ]] ; do

      debug "processing: $readline"

      mapfile -t returned_array < <( find_energy "$readline" )
      if (( ${#returned_array[@]} > 0 )) ; then
        debug "Array written, ${#returned_array[@]} elements"
        functional="${returned_array[0]}"
        energy="${returned_array[1]}"
        cycles="${returned_array[2]}"
        debug "functional=$functional; energy=$energy;"
        debug "cycles=$cycles"
        continue
        unset returned_array
      fi
      
      mapfile -t returned_array < <( find_temp_press "$readline" )
      if (( ${#returned_array[@]} > 0 )) ; then
        debug "Array written, ${#returned_array[@]} elements"
        temperature="${returned_array[0]}"
        pressure="${returned_array[1]}"
        debug "temperature=$temperature; pressure=$pressure"
        continue
        unset returned_array
      fi

      if [[ -z $zero_point_corr       ]] ; then 
        zero_point_corr=$(find_zero_point_corr "$readline") && continue 
      fi
      if [[ -z $thermal_corr_energy   ]] ; then 
        thermal_corr_energy=$(find_thermal_corr_energy "$readline") && continue 
      fi
      if [[ -z $thermal_corr_enthalpy ]] ; then 
        thermal_corr_enthalpy=$(find_thermal_corr_enthalpy "$readline") && continue 
      fi
      if [[ -z $thermal_corr_gibbs    ]] ; then 
        thermal_corr_gibbs=$(find_thermal_corr_gibbs "$readline") && continue 
      fi
      if [[ -z $entropy_tot           ]] ; then 
        # Placeholder
        entropy_tot="0123456.789" 
      fi
      if [[ -z $heatcap_tot           ]] ; then 
        # Placeholder
        heatcap_tot="0123456.789" 
      fi

    done < <(getlines_energy_g16_output_file "$logfile")

    if (( printlevel > 1 )) ; then
      print_energies_table \
        "$logfile" \
        "$functional" \
        "$temperature" \
        "$pressure" \
        "$energy" \
        "$zero_point_corr" \
        "$thermal_corr_energy" \
        "$thermal_corr_enthalpy" \
        "$thermal_corr_gibbs" \
        "$entropy_tot" \
        "$heatcap_tot"
    elif (( printlevel == 1 )) ; then
      print_energies_inline \
        "$logfile" \
        "$functional" \
        "$temperature" \
        "$pressure" \
        "$energy" \
        "$zero_point_corr" \
        "$thermal_corr_energy" \
        "$thermal_corr_enthalpy" \
        "$thermal_corr_gibbs" \
        "$entropy_tot" \
        "$heatcap_tot"
    elif (( printlevel == 0 )) ; then
      print_energies_inline \
        "$logfile" \
        "$energy" \
        "$zero_point_corr" \
        "$thermal_corr_enthalpy" \
        "$thermal_corr_gibbs" 
    fi

  else
    printf '%-25s No output file found.\n' "${testfile%.*}"
    return 1
  fi
}

print_energies_table ()
{
    echo "Calculation details:"
    printf '%-25s %8s: %-20s %-12s\n'    "File name"             ""       "${1}"  ""
    printf '%-25s %8s: %-20s %-12s\n'    "Functional"            ""       "${2}"  ""
    printf '%-25s %8s: %20.3f %-12s\n'   "Temperature"           "T"      "${3}"  "K"
    printf '%-25s %8s: %20.5f %-12s\n'   "Pressure"              "p"      "${4}"  "atm"
    printf '%-25s %8s: %+20.10f %-12s\n' "electronic en."        "E"      "${5}"  "Ha"
    printf '%-25s %8s: %+20.6f %-12s\n'  "zero-point corr."      "ZPE"    "${6}"  "Ha"
    printf '%-25s %8s: %+20.6f %-12s\n'  "thermal corr."         "U"      "${7}"  "Ha"
    printf '%-25s %8s: %+20.6f %-12s\n'  "ther. corr. enthalpy"  "H"      "${8}"  "Ha"
    printf '%-25s %8s: %+20.6f %-12s\n'  "ther. corr. Gibbs en." "G"      "${9}"  "Ha"
    printf '%-25s %8s: %+20.3f %-12s\n'  "entropy (total)"       "S tot"  "${10}" "cal/(mol K)"
    printf '%-25s %8s: %+20.3f %-12s\n'  "heat capacity (total)" "Cv tot" "${11}" "cal/(mol K)"
}

print_energies_inline ()
{
    local element printstring 
    local format="%s%-*s$separate_values"
    for element in "$@" ; do
      # shellcheck disable=SC2059
      printf -v printstring "$format" "$printstring" ${#element} "$element" 
    done
    echo "$printstring"
}

























#
# MAIN SCRIPT
#

# If this script is sourced, return before executing anything
(( ${#BASH_SOURCE[*]} > 1 )) && return 0

# Save how script was called
script_invocation_spell="$0 $*"

# Sent logging information to stdout
exec 3>&1

# Need to define debug function if unknown
if ! command -v debug ; then
  debug () {
    echo "DEBUG  : " "$*" >&4
  }
fi

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

get_scriptpath_and_source_files || exit 1

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
g16_tools_rc_loc="$(get_rc "$scriptpath" "/home/$USER" "$PWD")"
debug "g16_tools_rc_loc=$g16_tools_rc_loc"

# Load custom settings from the rc

if [[ ! -z $g16_tools_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-g16.bash/g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '$g16_tools_rc_loc' applied."
else
  debug "No custom settings found."
fi

# testing in progress

LC_NUMERIC="en_US.utf8"
process_one_file "$1" 0



#hlp   AUTHOR    : Martin
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
exit $exit_status
