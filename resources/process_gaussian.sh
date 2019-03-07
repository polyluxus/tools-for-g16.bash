#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

#
# Filename related functions
#

match_output_suffix ()
{
  local   allowed_input_suffix=(com in  inp gjf COM IN  INP GJF)
  local matching_output_suffix=(log out log log LOG OUT LOG LOG)
  local choices=${#allowed_input_suffix[*]} count
  local test_suffix="$1" return_suffix
  debug "test_suffix=$test_suffix; choices=$choices"
  
  # Assign matching outputfile
  for (( count=0 ; count < choices ; count++ )) ; do
    debug "count=$count"
    if [[ "$test_suffix" == "${matching_output_suffix[$count]}" ]]; then
      return_suffix="$extract_suffix"
      debug "Recognised output suffix: $return_suffix."
      break
    elif [[ "$test_suffix" == "${allowed_input_suffix[$count]}" ]]; then
      return_suffix="${matching_output_suffix[$count]}"
      debug "Matched output suffix: $return_suffix."
      break
    else
      debug "No match for $test_suffix; $count; ${allowed_input_suffix[$count]}; ${matching_output_suffix[$count]}"
    fi
  done

  [[ -z $return_suffix ]] && return 1

  echo "$return_suffix"
}

match_output_file ()
{
  # Check what was supplied and if it is read/writeable
  # Returns a filename
  local extract_suffix return_suffix basename
  local testfile="$1" return_file
  debug "Validating: $testfile"

  basename="${testfile%.*}"
  extract_suffix="${testfile##*.}"
  debug "basename=$basename; extract_suffix=$extract_suffix"

  if return_suffix=$(match_output_suffix "$extract_suffix") ; then
    return_file="$basename.$return_suffix"
  else
    return 1
  fi

  [[ -r $return_file ]] || return 1

  echo "$return_file"    
}

#
# Parsing functions
#

getlines_energy_g16_output_file ()
{
    local logfile="$1" logname
    logname=${logfile%.*}
    logname=${logname/\.\//}

    # Get the line for the electronic energy
    # Find match from the end of the file
    # Ref: http://unix.stackexchange.com/q/112159/160000
    # This is the slowest part.
    # If the calulation is a single point with a properties block it might
    # perform slower than $(grep -m1 'SCF Done' $logfile | tail -n 1).
    tac "$logfile" | grep -m1 "SCF Done"

    # Find all statements regarding the thermochemistry which are inline
    grep -e 'Temperature.*Pressure' \
      -e 'Zero-point correction' \
      -e 'Thermal correction to Energy' \
      -e 'Thermal correction to Enthalpy' \
      -e 'Thermal correction to Gibbs Free Energy' \
      "$logfile"
    # In the entropy block the given table needs to be transposed.
    # Heat capacity and the break up of the internal energy are usually not that important,
    # but they come as a freebie.
    local line pattern pattern_unit pattern_num index=0
    local -a header unit names thermal heatcap entropy
    while read -r line || [[ -n "$line" ]] ; do
      debug "Line: $line"
      pattern="^[[:space:]]*(E \\(Thermal\\))[[:space:]]+(CV)[[:space:]]+(S)"
      if [[ "$line" =~ $pattern ]] ; then
        header[1]="${BASH_REMATCH[1]}" # thermal
        header[2]="${BASH_REMATCH[2]}" # heatcap
        header[3]="${BASH_REMATCH[3]}" # entropy
        debug "Header: ${header[*]}"
        continue
      fi
      pattern_unit="[a-zA-Z/-]+"
      pattern="^[[:space:]]*($pattern_unit)[[:space:]]+($pattern_unit)[[:space:]]+($pattern_unit)[[:space:]]*$"
      if [[ "$line" =~ $pattern ]] ; then
        unit[1]="${BASH_REMATCH[1]}"
        unit[2]="${BASH_REMATCH[2]}"
        unit[3]="${BASH_REMATCH[3]}"
        debug "Units: ${unit[*]}"
        continue
      fi
      pattern_num="[-]?[0-9]+\\.[0-9]+"
      pattern="^[[:space:]]*([a-zA-Z]+)[[:space:]]+($pattern_num)[[:space:]]+($pattern_num)[[:space:]]+($pattern_num)[[:space:]]*$"
      if [[ "$line" =~ $pattern ]]; then
        names[$index]=${BASH_REMATCH[1]}
        thermal[$index]=${BASH_REMATCH[2]}
        heatcap[$index]=${BASH_REMATCH[3]}
        entropy[$index]=${BASH_REMATCH[4]}
        (( index++ ))
      fi
    done < <(grep -A6 -e 'E (Thermal)[[:space:]]\+CV[[:space:]]\+S' "$logfile")
    # Print them rearranged one value at the time
    index=0
    local format="%-30s= %20s %-10s\\n"
    while (( index < ${#names[@]} )) ; do
      # shellcheck disable=SC2059
      printf "$format" "${header[3]}[${names[$index]}]" "${entropy[$index]}" "${unit[3]}"
      # shellcheck disable=SC2059
      printf "$format" "${header[2]}[${names[$index]}]" "${heatcap[$index]}" "${unit[2]}"
      # shellcheck disable=SC2059
      printf "$format" "${header[1]}[${names[$index]}]" "${thermal[$index]}" "${unit[1]}"
      (( index ++ ))
    done
}

getlines_route_g16_output_file ()
{
    # The route section is echoed in the log file, but it might spread over various lines
    # options might be cut off in the middle. It always starts with # folowed by a space
    # or the various verbosity levels NPT (case insensitive). The route section is
    # terminated by a line of dahes. The script will stop reading the file if encountered.
    local line appendline pattern keepreading=false
    local logfile="$1"
    while read -r line || [[ -n "$line" ]] ; do
      pattern="^[[:space:]]*#[nNpPtT]?[[:space:]]"
      if [[ $line =~ $pattern || "$keepreading" == "true" ]] ; then
        [[ $line =~ ^[[:space:]]*[-]+[[:space:]]*$ ]] && break
        appendline="$appendline$line"
        keepreading=true
      fi
    done < "$logfile"
    echo "$appendline"
}

find_energy ()
{
    local readline="$1"
    # Initiate variables necessary for parsing output
    local readline pattern pattern_num equals unit
    local functional energy cycles
    # Find match from the end of the file 
    # Ref: http://unix.stackexchange.com/q/112159/160000
    # This is the slowest part. 
    # If the calulation is a single point with a properties block it might 
    # perform slower than $(grep -m1 'SCF Done' $logfile | tail -n 1).
    # Gaussian output has following format, trap important information:
    # Method, Energy, Cycles
    # Example taken from BP86/cc-pVTZ for water (H2O): 
    #  SCF Done:  E(RB-P86) =  -76.4006006969     A.U. after   10 cycles
    pattern_num="[-]?[0-9]+\\.[0-9]+"
    equals="[[:space:]]+=[[:space:]]+"
    unit="[[:space:]]+[aA]\\.[uU]\\.[^0-9]+"
    pattern="E\\(([^\\)]+)\\)$equals($pattern_num)$unit([0-9]+) cycles"
    debug "$pattern"
    if [[ $readline =~ $pattern ]] ; then 
      functional="${BASH_REMATCH[1]}"
      energy="${BASH_REMATCH[2]}"
      cycles="${BASH_REMATCH[3]}"

      debug "functional='$functional'; energy='$energy'; cycles='$cycles'"
      # Print the line, format it for table like structure
      echo "$functional" 
      echo "$energy" 
      echo "$cycles"
    else
      debug "No energy statement found."
      return 1
    fi
}

find_temp_press ()
{
    local readline="$1" pattern pattern_temp pattern_pres
    pattern_temp="Temperature[[:space:]]+([0-9]+\\.[0-9]+)[[:space:]]+Kelvin\\."
    pattern_pres="Pressure[[:space:]]+([0-9]+\\.[0-9]+)[[:space:]]+Atm\\."
    pattern="^[[:space:]]*${pattern_temp}[[:space:]]+${pattern_pres}[[:space:]]*$"
    if [[ $readline =~ $pattern ]] ; then
      debug "temperature: ${BASH_REMATCH[1]}; pressure: ${BASH_REMATCH[1]}"
      echo "${BASH_REMATCH[1]}" # Temperature
      echo "${BASH_REMATCH[2]}" # Pressure
    else
      debug "Temperature and Pressure not within this line."
      return 1
    fi
}

find_zero_point_corr ()
{
    local readline="$1" pattern
    pattern="Zero-point correction=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    if [[ $readline =~ $pattern ]] ; then
      debug "Zero-point correction: ${BASH_REMATCH[1]}"
      echo "${BASH_REMATCH[1]}" 
    else
      debug "Zero-point correction not within this line."
      return 1
    fi
}

find_thermal_corr_energy ()
{
    local readline="$1" pattern
    pattern="Thermal correction to Energy=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    if [[ $readline =~ $pattern ]] ; then
      debug "Thermal correction to Energy: ${BASH_REMATCH[1]}"
      echo "${BASH_REMATCH[1]}" 
    else
      debug "Thermal correction to Energy not within this line."
      return 1
    fi
}

find_thermal_corr_enthalpy ()
{
    local readline="$1" pattern
    pattern="Thermal correction to Enthalpy=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    if [[ $readline =~ $pattern ]] ; then
      debug "Thermal correction to Enthalpy: ${BASH_REMATCH[1]}"
      echo "${BASH_REMATCH[1]}" 
    else
      debug "Thermal correction to Enthalpy not within this line."
      return 1
    fi
}

find_thermal_corr_gibbs ()
{
    local readline="$1" pattern
    pattern="Thermal correction to Gibbs Free Energy=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    if [[ $readline =~ $pattern ]] ; then
      debug "Thermal correction to Gibbs Free Energy: ${BASH_REMATCH[1]}"
      echo "${BASH_REMATCH[1]}" 
    else
      debug "Thermal correction to Gibbs Free Energy not within this line."
      return 1
    fi
}

find_entropy ()
{
    # This function doubles as a means to find the total entropy,
    # as well as the contributions,
    # this is in principle just a safeguard if I get my code a bit wrong
    local readline="$1" pattern subpattern
    debug "Read: $readline"
    debug "Option: '$2'"
    case $2 in
      ""|[Tt][Oo][Tt]*)
        subpattern="Total" ;;
      [Ee][Ll][Ee]*)
        subpattern="Electronic" ;;
      [Tt][Rr][Aa]*)
        subpattern="Translational" ;;
      [Rr][Oo][Tt]*)
        subpattern="Rotational" ;;
      [Vv][Ii][Bb]*)
        subpattern="Vibrational" ;;
      *)
        debug "No match for '$2'."
        subpattern="Total" ;;
    esac
    # the line has already been transformed from the g16 original output
    pattern="S\\[($subpattern)\\][[:space:]]+=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    debug "Matching: '$pattern'"
    if [[ $readline =~ $pattern ]] ; then
      debug "Found entropy (${BASH_REMATCH[1]}): ${BASH_REMATCH[2]}"
      echo "${BASH_REMATCH[2]}" 
    else
      debug "Entropy not within this line."
      return 1
    fi
}

find_heatcapacity ()
{
    # This function doubles as a means to find the total heat capacity,
    # as well as the contributions,
    # this is in principle just a safeguard if I get my code a bit wrong
    local readline="$1" pattern subpattern
    debug "Read: $readline"
    case $2 in
      ""|[Tt][Oo][Tt]*)
        subpattern="Total" ;;
      [Ee][Ll][Ee]*)
        subpattern="Electronic" ;;
      [Tt][Rr][Aa]*)
        subpattern="Translational" ;;
      [Rr][Oo][Tt]*)
        subpattern="Rotational" ;;
      [Vv][Ii][Bb]*)
        subpattern="Vibrational" ;;
      *)
        debug "No match for '$2'."
        subpattern="Total" ;;
    esac
    # the line has already been transformed from the g16 original output
    pattern="CV\\[($subpattern)\\][[:space:]]+=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    debug "Matching: '$pattern'"
    if [[ $readline =~ $pattern ]] ; then
      debug "Found heat capacity (${BASH_REMATCH[1]}): ${BASH_REMATCH[2]}"
      echo "${BASH_REMATCH[2]}" 
    else
      debug "Heat capacity not within this line."
      return 1
    fi
}

find_thermal_corr ()
{
    # This function doubles as a means to find the total heat capacity,
    # as well as the contributions,
    # this is in principle just a safeguard if I get my code a bit wrong
    local readline="$1" pattern subpattern
    debug "Read: $readline"
    case $2 in
      ""|[Tt][Oo][Tt]*)
        subpattern="Total" ;;
      [Ee][Ll][Ee]*)
        subpattern="Electronic" ;;
      [Tt][Rr][Aa]*)
        subpattern="Translational" ;;
      [Rr][Oo][Tt]*)
        subpattern="Rotational" ;;
      [Vv][Ii][Bb]*)
        subpattern="Vibrational" ;;
      *)
        debug "No match for '$2'."
        subpattern="Total" ;;
    esac
    # the line has already been transformed from the g16 original output
    pattern="E \\(Thermal\\)\\[($subpattern)\\][[:space:]]+=[[:space:]]+([-]?[0-9]+\\.[0-9]+)"
    debug "Matching: '$pattern'"
    if [[ $readline =~ $pattern ]] ; then
      debug "Found heat capacity (${BASH_REMATCH[1]}): ${BASH_REMATCH[2]}"
      echo "${BASH_REMATCH[2]}" 
    else
      debug "Heat capacity not within this line."
      return 1
    fi
}

# 
# Routines for parsing the link0 commands 
#

parse_link0 ()
{
    # link0 directives are before the route section
    # index let's you choose which part of the buffer should be returned
    local parseline="$1"
    local pattern="$2"
    local index="$3"
    if [[ $parseline =~ $pattern ]]; then
        echo "${BASH_REMATCH[$index]}"
    else 
        return 1
    fi
}

get_chk_file ()
{
    # The checkpointfile should be indicated in the original input file
    # (It is a link 0 command and should therefore be before the route section.)
    local parseline="$1"
    local pattern="^[[:space:]]*%[Cc][Hh][Kk]=([^[:space:]]+)([[:space:]]+|$)"
    # Only the filename (index 1) should be returned
    local rematch_index=1
    debug "Testing for checkpoint file."
    checkpoint=$(parse_link0 "$parseline" "$pattern" "$rematch_index") || return 1
    debug "Checkpoint file is '$checkpoint'"
}

get_oldchk_file ()
{
    local parseline="$1"
    local pattern="^[[:space:]]*%[Oo][Ll][Dd][Cc][Hh][Kk]=([^[:space:]]+)([[:space:]]+|$)"
    # The whole match (line, index 0) needs to be returned
    local rematch_index=1 
    debug "Testing for OldChk."
    old_checkpoint=$(parse_link0 "$parseline" "$pattern" "$rematch_index") || return 1
    debug "Link0 directive '%OldChk=$old_checkpoint' found."
}

warn_nprocs_directive ()
{
    # The nprocs directive should be removed/replaced by the submission script
    local parseline="$1"
    local pattern="^[[:space:]]*%[Nn][Pp][Rr][Oo][Cc][Ss][Hh][Aa][Rr][Ee][Dd]=([^[:space:]]+)([[:space:]]+|$)"
    # The whole match (line, index 0) needs to be returned
    local rematch_index=0
    local nprocs_read
    debug "Testing for NProcShared."

    if nprocs_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") ; then
      warning "Link0 directive '$nprocs_read' found. " # will be substituted with script settings (?)
      return 0
    else
      debug "Not a NProcShared statement."
      return 1
    fi
}

warn_mem_directive ()
{
    # The mem directive needs to be adapted, i.e. removed/replaced with system values
    local parseline="$1"
    local pattern="^[[:space:]]*%[Mm][Ee][Mm]=([^[:space:]]+)([[:space:]]+|$)"
    # The whole match (line, index 0) needs to be returned
    local rematch_index=0
    local memory_read
    debug "Testing for memory."

    if memory_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") ; then 
      warning "Link0 directive '$memory_read' found." # will be substituted with script settings (?)
      return 0
    else
      debug "Not a memory statement."
      return 1
    fi
}

# other link0 derectives should be appended here if necessary

#
# Parse input files
#

remove_g16_input_comment ()
{
    debug "Attempting to remove comment."
    local parseline="$1"
    debug "Parsing: '$parseline'"
    local pattern="^[[:space:]]*([^!]+)[!]*[[:space:]]*(.*)$"
    if [[ $parseline =~ $pattern ]] ; then
      debug "Matched: ${BASH_REMATCH[0]}"
      # Return the line without the comment part
      echo "${BASH_REMATCH[1]}"
      [[ -n ${BASH_REMATCH[2]} ]] && message "Removed comment: ${BASH_REMATCH[2]}"
      debug "Line without comment: '${BASH_REMATCH[1]}' (Return 0.)"
      return 0
    elif [[ $parseline =~ ^!(.*)$ ]] ; then
      message "Removed comment: ${BASH_REMATCH[1]}"
      debug "The whole line is a comment. (Return 0.)"
      return 0
    else
      debug "Line is blank. (Return 1.)"
      return 1 # Return false if blank line
    fi
}

read_xyz_geometry_file ()
{
    debug "Reading input file."
    local parsefile="$1" line storeline
    debug "Working on: $parsefile"
    local pattern pattern_num pattern_element pattern_print
    local         pattern_coord skip_reading_coordinates="no" convert_coord2xyz="no"
    local -a      inputfile_coord2xyz
    local         pattern_charge pattern_mult pattern_uhf
    # A global variable called 'inputfile_body' should start with the geometry
    # Other content is stored in global variables 'title_section', 'molecule_charge', 'molecule_mult'
    local molecule_charge_local molecule_mult_local molecule_uhf_local
    local body_index=0
    pattern_coord="^[[:space:]]*\\\$coord[[:space:]]*$"
    pattern_num="[+-]?[0-9]+\\.[0-9]*"
    pattern_element="[A-Za-z]+[A-Za-z]*"
    pattern="^[[:space:]]*($pattern_element)[[:space:]]*($pattern_num)[[:space:]]*($pattern_num)[[:space:]]*($pattern_num)[[:space:]]*(.*)$"
    pattern_print="%-3s %15.8f %15.8f %15.8f"
    pattern_charge="[Cc][Hh][Rr][Gg][[:space:]]*([+-]?[0-9]+)"
    pattern_mult="[Mm][Uu][Ll][Tt][[:space:]]*([0-9]+)"
    pattern_uhf="[Uu][Hh][Ff][[:space:]]*([0-9]+)"
    while read -r line || [[ -n "$line" ]] ; do
      debug "Read line: $line"
      
      if [[ "$skip_reading_coordinates" =~ [Nn][Oo] ]] ; then
        if [[ "$line" =~ $pattern_coord ]] ; then
          message "This appears to be a file in Turbomole format."
          message "File will be converted using openbabel."
          skip_reading_coordinates="yes"
          convert_coord2xyz="yes"
        else
          debug "Not a coord file."
        fi

        if [[ "$line" =~ $pattern ]] ; then
          # shellcheck disable=SC2059
          storeline=$(printf "$pattern_print" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
          debug "Ignored end of line: '${BASH_REMATCH[5]}'."
          inputfile_body[$body_index]="$storeline" 
          debug "Read and stored: '${inputfile_body[$body_index]}'"
          (( body_index++ ))
          debug "Increase index to $body_index."
          continue
        else
          debug "Line doesn't match pattern of xyz."
        fi
      fi

      if [[ "$line" =~ $pattern_charge ]] ; then
        molecule_charge_local="${BASH_REMATCH[1]}"
        message "Found molecule's charge: $molecule_charge_local."
        if [[ -n $molecule_charge ]] && (( molecule_charge != molecule_charge_local )) ; then
          warning "Overwriting previously set charge ($molecule_charge)."
        fi
        molecule_charge="$molecule_charge_local"
        debug "Use molecule's charge: $molecule_charge."
      fi
      if [[ "$line" =~ $pattern_mult ]] ; then
        molecule_mult_local="${BASH_REMATCH[1]}"
        message "Found molecule's multiplicity: $molecule_mult_local."
        if [[ -n $molecule_mult ]] && (( molecule_mult != molecule_mult_local )) ; then
          warning "Overwriting previously set multiplicity ($molecule_mult)."
        fi
        molecule_mult="$molecule_mult_local"
        debug "Use molecule's multiplicity: $molecule_mult."
      fi
      if [[ "$line" =~ $pattern_uhf ]] ; then
        molecule_uhf_local="${BASH_REMATCH[1]}"
        message "Found number of unpaired electrons for the molecule: $molecule_uhf_local."
        molecule_mult_local="$(( molecule_uhf_local + 1 ))"
        debug "Converted to multiplicity: $molecule_mult_local"
        if [[ -n $molecule_mult ]] && (( molecule_mult != molecule_mult_local )) ; then
          warning "Overwriting previously set multiplicity ($molecule_mult)."
        fi
        molecule_mult="$molecule_mult_local"
        message "Use molecule's multiplicity: $molecule_mult."
      fi

    done < "$parsefile"

    if [[ "$convert_coord2xyz" =~ [Yy][Ee][Ss] ]] ; then
      local tmplog 
      tmplog=$(mktemp tmp.XXXXXXXX) 
      debug "$(ls -lh "$tmplog")"
      mapfile -t inputfile_coord2xyz < <("$obabel_cmd" -itmol "$parsefile" -oxyz 2> "$tmplog")
      debug "$(cat "$tmplog")"
      debug "$(rm -v -- "$tmplog")"

      # First line is the number of atoms.
      # Second line is a comment.
      unset 'inputfile_coord2xyz[0]' 'inputfile_coord2xyz[1]'
      debug "$(printf '%s\n' "${inputfile_coord2xyz[@]}")"
      if (( ${#inputfile_body[@]} > 0 )) ; then
        warning "Input file body has previously been written to."
        warning "The following content will be overwritten:"
        warning "$(printf '%s\n' "${inputfile_body[@]}")"
      fi
      inputfile_body=( "${inputfile_coord2xyz[@]}" )
    else
      debug "Inputfile doesn't need conversion from Turbomol to Xmol format."
    fi

    if (( ${#inputfile_body[@]} == 0 )) ; then
      warning "No geometry in '$parsefile'." 
      return 1
    fi
    debug "Finished reading input file."
}

read_g16_input_file ()
{
    # The route section contains one or more lines.
    # It always starts with # folowed by a space or the various verbosity levels 
    # NPT (case insensitive). The route section is terminated by a blank line.
    # This must always be present. 
    # The next two entries may be present (but only together).
    # It is immediately followed by the title section, which can also consist of 
    # multiple lines made up of (almost) anything. It is also terminated by a blank line.
    # Following that is the charge and multiplicity of the molecule and all defined fragments.
    # After that come geometry and other input sections, we trust the user knows how to
    # specify these and read them as they are.

    debug "Reading input file."
    local parsefile="$1" line appendline pattern
    debug "Working on: $parsefile"
    # The hash marks the beginning of the route (everything before is link0)
    local route_start_pattern="^[[:space:]]*#[nNpPtT]?([[:space:]]|$)"
    # which will be stored in the global variable 'route_section'
    # We need to store link0 as an array, which is a global variable called 'inputfile_link0'
    local store_link0=1 link0_index=0 link0_temp
    # Flags when to read what
    local store_route=0 store_title=0 store_charge_mult=0 
    # content stored in global variables 'title_section', 'molecule_charge', 'molecule_mult', 'molecule_fragments'
    # The remainder of the inputfile also goes into an array, 
    # which is a global variable called 'inputfile_body'
    local body_index=0

    while read -r line || [[ -n "$line" ]] ; do
      debug "Read line: $line"
      if (( store_link0 == 1 )) ; then
        line=$(remove_g16_input_comment "$line") || fatal "There appears to be a blank line in Link0. Abort."
        # There is only one directive per line, there must not be a blank line
        if [[ -z $checkpoint ]] ; then
          # If the chk directive is found, check the next line
          get_chk_file "$line" && continue
          debug "Checkpoint file not found."
        fi
        if [[ -z $old_checkpoint ]] ; then
          # If the chk directive is found, check the next line
          get_oldchk_file "$line" && continue
          debug "Old checkpoint file not found."
        fi
        if warn_nprocs_directive "$line" ; then
          # If the nprocs directive is found a warning will be issued,
          # add that the directive will be ignored.
          warning "The statement will be replaced by script values."
          # Skip to the next line if the statement was found.
          continue
        fi
        if warn_mem_directive "$line" ; then
          # If the mem directive is found a warning will be issued,
          # add that the directive will be ignored.
          warning "The statement will be replaced by script values."
          # Skip to the next line if the statement was found.
          continue
        fi

        # Setting the pattern to the form '%<directive>=<content>'
        # will not match link0 directives like %Save/%NoSave, ergo the following is bogus:
        # pattern="^[[:space:]]*%([^=]+)=([^[:space:]]+)([[:space:]]+|$)"
        # Therefore match anything tht contains a %[A-Za-z]
        pattern="^[[:space:]]*(%[A-Za-z]+)(.*)$"
        if link0_temp=$(parse_link0 "$line" "$pattern" "0") ; then
          # If anything is found, everything (rematch index 0) must be stored
          inputfile_link0[$link0_index]="$link0_temp"
          debug "Extra link0 directive saved: ${inputfile_link0[$link0_index]}"
          (( link0_index++ ))
          continue
        else
          debug "Read line does not appear to be a link0 directive. Switch off reading link0."
          # If the pattern is not found, the link0 directives are completed,
          # switch reading off.
          store_link0=2
        fi
      fi

      if (( store_route == 0 )) ; then
        if [[ $line =~ $route_start_pattern ]] ; then
          debug "Read line contains route start pattern. Start reading route section."
          # Start reading the route section end reading link0 directives
          store_route=1
          route_section=$(remove_g16_input_comment "$line")
          # Read next line
          continue
        else
          debug "Read line does not contain route start pattern."
        fi
      elif (( store_route == 1 )) ; then
        # Cannot have start to store the route and continue to read it at the same time
        debug "Still reading route section."
        # Still reading the route section
        if [[ $line =~ ^[[:space:]]*$ ]]; then
          # End reading route when blank line is encountered
          # and start reading the title
          debug "Blank line encountered. Route section is finished."
          store_title=1
          store_route=2
          if check_allcheck_option "$route_section" ; then
            message "Skipping reading title, charge, and multiplicity."
            store_title=2
            store_charge_mult=2
          else
            debug "Title, charge, and multiplicity need to be read."
          fi
          # If we are here, the line is blank, 
          # we don't need to parse that and can read the next one
          continue
        fi

        # There could be another hashtag. It does not hurt, but we can safely remove it, too.
        local route_cont_pattern="^([[:space:]]*#([[:space:]]*[nNpPtT][[:space:]])?)"
        if [[ $line =~ $route_cont_pattern ]] ; then
          debug "Read line contains another route start pattern: '${BASH_REMATCH[0]}'"
          line="${line:${#BASH_REMATCH[0]}}"
          debug "Line after removing pattern: $line"
        fi
        # Clean line from comments, store in 'appendline' buffer
        appendline=$(remove_g16_input_comment "$line") 
        # there might be comment only lines which can be removed/ ignored
        [[ -n $appendline ]] && route_section="$route_section $appendline"
        # prepare for next read (just to be sure)
        unset appendline
        # Read next line
        continue
      else
        debug "Not storing route section. (store_route=$store_route)"
      fi
      if (( store_title == 1 )) ; then
        debug "Reading title section."
        if [[ $line =~ ^[[:space:]]*$ ]]; then
          # End reading title after blank line is encountered
          store_title=2
          store_charge_mult=1
          debug "Finished title section: $title_section"
          # If we are here, the line is blank, read next line
          continue
        fi
        # The title section is free form (no comment removing) (no comment removing)
        appendline="$line"
        if [[ -z $title_section ]] ; then 
          title_section="$appendline"
        else
          title_section="$title_section $appendline"
        fi
        unset appendline
        continue
      else
        debug "Not storing title section. (store_title=$store_title)"
      fi
      if (( store_charge_mult == 1 )) ; then
        debug "Reading charge and multiplicity."
        appendline=$(remove_g16_input_comment "$line") 
        # Define how the items can be separated
        local separator="[[:space:]]*[,[:space:]][[:space:]]*"
        # Change the pattern to the '<+/-><number>< ,><number><extra stuff for fragments>' format
        # This will take care of the overall molecule specification
        pattern="^[[:space:]]*([+-]?[0-9]+)$separator([0-9]+)(.*)$"
        if [[ $appendline =~ $pattern ]] ; then
          molecule_charge="${BASH_REMATCH[1]}"
          molecule_mult="${BASH_REMATCH[2]}"
          appendline="${BASH_REMATCH[3]}"
          debug "Read charge ($molecule_charge) and multiplicity ($molecule_mult)."
          debug "Remaining: '$appendline'"
        fi
        # Redefine the pattern to match fragment specifications, may start with a separator
        # < ,><+/-><number>< ,><+/-><number>
        pattern="^$separator([+-]?[0-9]+)$separator([+-]?[0-9]+)(.*)?$"
        # define local arrays to hold fragment information
        local -a fragment
        local fragment_charge fragment_mult
        while [[ $appendline =~ $pattern ]] ; do
          debug "Testing for fragments."
          fragment_charge="${BASH_REMATCH[1]}"
          fragment_mult="${BASH_REMATCH[2]}"
          appendline="${BASH_REMATCH[3]}"
          fragment+=( "$fragment_charge" "$fragment_mult" )
          debug "Read fragment charge (${fragment[-2]}) and multiplicity (${fragment[-1]})."
          debug "Remaining: '$appendline'"
        done
        if [[ $appendline =~ ^[[:space:]]*$ ]] ; then
          unset appendline
        else
          warning "Ignoring extra content '$appendline' from charge/multiplicity line."
          unset appendline
        fi
        # Issue some warnings
        (( ${#fragment[@]} % 2 == 1 )) && warning "Unpaired charge/multiplicity present, input probably corrupted."
        (( ${#fragment[@]} / 2 == 1 )) && warning "Only one fragment charge/multiplicity present."

        # Store fragment information on one string
        if (( ${#fragment[@]} > 0 )) ; then
          molecule_fragments="$( printf ' %s, %s  ' "${fragment[@]}" )"
        else
          unset molecule_fragments
        fi
        debug "Read fragments: $molecule_fragments"

        store_charge_mult=2
        # Next should be geometry and other stuff
        continue
      else
        debug "Not storing charge/ multiplicity. (store_charge_mult=$store_charge_mult)"
      fi
      
      debug "Reading rest of input file. All reads should be 2 now (otherwise problem)."
      debug "store_link0=$store_link0; store_route=$store_route; store_title=$store_title; store_charge_mult=$store_charge_mult"
      if line=$(remove_g16_input_comment "$line") ; then
        # Empty lines will be kept (because above will be false)
        debug "Checking line '$line' is empty after removing comment."
        # If _after_ removing the comment the line is empty, skip to the next line
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        debug "Read line is not empty, it will be kept."
      else
        debug "Empty line will be kept."
      fi

      inputfile_body[$body_index]="$line" 
      debug "Read and stored: '${inputfile_body[$body_index]}'"
      (( body_index++ ))
      debug "Increase index to $body_index."

    done < "$parsefile"
    debug "Finished reading input file."
}

#
# Functions to modify input strings
#

collate_route_keyword_opts ()
{
    # The function takes an inputstring and removes any unnecessary spaces
    # needed for collate_route_keywords
    debug "Collating keyword options."
    local inputstring="$1"
    debug "Input: $inputstring"
    # The collated section will be saved to
    local keepstring transformstring
    # Any combination of spaces, equals signs, and opening parentheses
    # can and need to be removed
    local remove_front="[[:space:]]*[=]?[[:space:]]*[\\(]?"
    # Any trailing closing parentheses and spaces need to be cut
    local remove_end="[\\)]?[[:space:]]*"
    local pattern="$remove_front([^\\)]+)$remove_end"
    [[ $inputstring =~ $pattern ]] && inputstring="${BASH_REMATCH[1]}"
    
    # Spaces, tabs, or commas can be used in any combination
    # to separate items within the options.
    # Does massacre IOPs.
    pattern="[^[:space:],]+([[:space:]]*=[[:space:]]*[^[:space:],]+)?([[:space:],]+|$)"
    while [[ $inputstring =~ $pattern ]] ; do
      transformstring="${BASH_REMATCH[0]}"
      inputstring="${inputstring//${BASH_REMATCH[0]}/}"
      # remove stuff
      transformstring="${transformstring// /}"
      transformstring="${transformstring//,/}"
      if [[ -z $keepstring ]] ; then
        keepstring="$transformstring"
      else
        keepstring="$keepstring,$transformstring"
      fi
    done
    echo "$keepstring"
    debug "Returned: $keepstring"
}

collate_route_keywords ()
{
    # This function removes spaces which have been entered in the original input
    # so that the folding (to 80 characters) doesn't break a keyword.
    debug "Collating keywords."
    local inputstring="$1"
    debug "Input: $inputstring"
    # The collated section will be saved to
    local keepstring
    # If we encounter a long keyword stack, we need to set a different returncode
    # to issue a warning
    local returncode=0
    # extract the hashtag of the route section
    local route_start_pattern="^[[:space:]]*(#[nNpPtT]?)[[:space:]]"
    if [[ $inputstring =~ $route_start_pattern ]] ; then
      keepstring="${BASH_REMATCH[1]}"
      inputstring="${inputstring//${BASH_REMATCH[0]}/}"
      debug "Saved to route: $keepstring"
      debug "Remaining to parse: $inputstring"
    fi

    # The following formats for the input of keywords are given in the manual:
    #   keyword = option
    #   keyword(option)
    #   keyword=(option1, option2, …)
    #   keyword(option1, option2, …)
    # Spaces can be added or left out, I could also confirm that the following will work, too:
    #   keyword (option[1, option2, …])
    #   keyword = (option[1, option2, …])
    # Spaces, tabs, commas, or forward slashes can be used in any combination 
    # to separate items within a line. 
    # Multiple spaces are treated as a single delimiter.
    # see http://gaussian.com/input/?tabid=1
    # The ouptput of this function should only use the keywords without any options, or
    # the following format: keyword(option1,option2,…) [no spaces]
    # Exeptions to the above: temperature=500 and pressure=2, 
    # where the equals is the only accepted form.
    # This is probably because they can also be options to 'freq'.
    # Hashes can also appear (apparently) everywhere, but only the first is actually needed

    # Note: double backslash in double quotes https://github.com/koalaman/shellcheck/wiki/SC1117
    
    local keyword_pattern="[^[:space:],/\\(=]+"
    local option_pattern_equals="[[:space:]]*=[[:space:]]*[^[:space:],/\\(\\)]+"
    local option_pattern_parens="[[:space:]]*[=]?[[:space:]]*\\([^\\)]+\\)"
    local keyword_options="$option_pattern_equals|$option_pattern_parens"
    local keyword_terminate="[[:space:],/]+|$"
    local test_pattern="($keyword_pattern)($keyword_options)?($keyword_terminate)"
    local keep_keyword keep_options
    local numerical_pattern="[[:digit:]]+\\.?[[:digit:]]*"
    while [[ $inputstring =~ $test_pattern ]] ; do
      # Unify input pattern and remove unnecessary spaces
      # Remove found portion from inputstring:
      debug "Splitting up: ${BASH_REMATCH[0]}"
      inputstring="${inputstring//${BASH_REMATCH[0]}/}"
      debug "Remaining to parse (later): $inputstring"
      # Keep keword, options, and how it was terminated
      keep_keyword="${BASH_REMATCH[1]}"
      keep_options="${BASH_REMATCH[2]}"
      keep_terminate="${BASH_REMATCH[3]}"
      debug "keep_keyword=$keep_keyword; keep_options=$keep_options; keep_terminate=$keep_terminate"

      # Remove spaces from IOPs (only evil people use them there)
      if [[ $keep_keyword =~ ^[Ii][Oo][Pp]$ ]] ; then
        keep_keyword="$keep_keyword$keep_options"
        keep_keyword="${keep_keyword// /}"
        unset keep_options # unset to not run into next 'if'
        debug "Mathed an IOP (this is an exception to the rule)."
      fi

      if [[ -n $keep_options ]] ; then 
        # remove spaces, equals, parens from front and end
        # substitute option separating spaces with commas
        keep_options=$(collate_route_keyword_opts "$keep_options")

        # Check for the exceptions to the desired format
        if [[ $keep_keyword =~ ^[Tt][Ee][Mm][Pp].*$ ]] ; then
          if [[ ! $keep_options =~ ^$numerical_pattern$ ]] ; then
            warning "Unrecognised format for temperature: $keep_options."
            returncode=1
          fi
          keep_keyword="$keep_keyword=$keep_options"
        elif [[ $keep_keyword =~ ^[Pp][Rr][Ee].*$ ]] ; then
          if [[ ! $keep_options =~ ^$numerical_pattern$ ]] ; then
            warning "Unrecognised format for pressure: $keep_options."
            returncode=1
          fi
          keep_keyword="$keep_keyword=$keep_options"
        elif [[ $keep_keyword =~ ^[Mm][Aa][Xx][Dd][Ii][Ss][Kk].* ]] ; then
          if [[ ! $keep_options =~ ^${numerical_pattern}([KkMmGgTt][BbWw])?$ ]] ; then
            warning "Unrecognised format for MaxDisk: $keep_options."
            returncode=1
          fi
          keep_keyword="$keep_keyword=$keep_options"
        else
          keep_keyword="$keep_keyword($keep_options)"
        fi
      fi
      if [[ $keep_terminate =~ / ]] ; then
        keep_keyword="$keep_keyword/"
      fi
      if (( ${#keep_keyword} > 80 )) ; then
        returncode=1
        warning "Found extremely long keyword, folding route section might break input."
      fi
      debug "Saved keyword to route: $keep_keyword"
      if [[ $keepstring =~ /$ ]] ; then
        keepstring="$keepstring$keep_keyword"
      elif [[ -z $keepstring ]] ; then
        keepstring="$keep_keyword"
      else
        keepstring="$keepstring $keep_keyword"
      fi
    done

    echo "$keepstring"
    debug "Return: $keepstring"
    return $returncode
}

#
# Functions to modify the route section
#

remove_any_keyword ()
{
    # Takes in a string (the route section, or part of it) and 
    local test_line="$1"
    # removes the pattern (keyword) if present and 
    local test_pattern="$2"
    # returns the result.
    local return_line
    # Since spaces should have been removed form within the keywords previously with collate_route_keywords, 
    # and inter-keyword delimiters are set to spaces only also, 
    # it is safe to use that as a criterion to remove unnecessary keywords.
    # The test pattern is extended to catch the whole keyword including options.
    local extended_test_pattern="(${test_pattern}[^[:space:]]*)([[:space:]]+|$)"
    if [[ $test_line =~ $extended_test_pattern ]] ; then
      local found_pattern=${BASH_REMATCH[1]}
      debug "Found pattern: '$found_pattern'" 
      message "Removed keyword '$found_pattern'."
      return_line="${test_line/$found_pattern/}"
      echo "$return_line"
      return 1
    else
      echo "$test_line"
      return 0 
    fi
}

remove_maxdisk_keyword ()
{
    # Assigns the maxdisk keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Mm][Aa][Xx][Dd][Ii][Ss][Kk]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_opt_keyword ()
{
    # Assigns the opt keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Oo][Pp][Tt]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_freq_keyword ()
{
    # Assigns the freq keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Ff][Rr][Ee][Qq]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_irc_keyword ()
{
    # Assigns the irc keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Ii][Rr][Cc]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_scrf_keyword ()
{
    # Assigns the scrf keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Ss][Cc][Rr][Ff]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_temp_keyword ()
{
    # Assigns the temp keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Tt][Ee][Mm][Pp]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_pressure_keyword ()
{
    # Assigns the pressure keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Pp][Rr][Ee][Ss][Ss][Uu][Rr][Ee]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_guess_keyword ()
{
    # Assigns the guess keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Gg][Uu][Ee][Ss][Ss]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_geom_keyword ()
{
    # Assigns the geom keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Gg][Ee][Oo][Mm]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_gen_keyword ()
{
    # Assigns the gen keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Gg][Ee][Nn]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_pop_keyword ()
{
    # Assigns the pop keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Pp][Oo][Pp]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

remove_output_keyword ()
{
    # Assigns the pop keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Oo][Uu][Tt][Pp][Uu][Tt]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

# Others (?)

#
# Checks for keywords (and syntax)
#

check_any_keyword ()
{
    local parseline="$1"
    local pattern="$2"
    local keyword_alias="$3"
    debug "Read: '$parseline'."
    debug "Pattern: '$pattern'."
    if [[ $parseline =~ $pattern ]] ; then
      debug "Keword found in input stream. Returning with 0."
      return 0
    fi
    debug "Keword not found in input stream. Returning with 1."
    return 1
}

# check for AllCheck because then we have to omit title and multiplicity
check_allcheck_option ()
{   
    debug "Checking if the AllCheck keyword is set in the route section."
    # Assigning the allcheck option to the pattern
    local parseline="$1"
    local pattern="[Aa][Ll][Ll][Cc][Hh][Ee][Cc][Kk]"
    local keyword_alias="AllCheck"
    debug "Checking '$parseline' for pattern '$pattern'. Description: '$keyword_alias'."
    if check_any_keyword "$parseline" "$pattern" ; then
      message "Keyword '$keyword_alias' found in input stream."
      debug "Again returning with 0."
      return 0
    fi
    debug "Keyword '$keyword_alias' not found. (Return 1)"
    return 1
}

check_freq_keyword ()
{
    debug "Checking if the Freq keyword is set in the route section."
    # Assigning the freq option to the pattern
    local parseline="$1"
    local pattern="[Ff][Rr][Ee][Qq]"
    local keyword_alias="Freq"
    debug "Checking '$parseline' for pattern '$pattern'. Description: '$keyword_alias'."
    if check_any_keyword "$parseline" "$pattern" ; then
      message "Keyword '$keyword_alias' found in input stream."
      debug "Again returning with 0."
      return 0
    fi
    debug "Keyword '$keyword_alias' not found. (Return 1)"
    return 1
}

check_denfit_keyword ()
{
    debug "Checking if the Denfit keyword is set in the route section."
    # Assigning the denfit option to the pattern
    local parseline="$1"
    local pattern="[Dd][Ee][Nn][Ff][Ii][Tt]"
    local keyword_alias="Denfit"
    debug "Checking '$parseline' for pattern '$pattern'. Description: '$keyword_alias'."
    if check_any_keyword "$parseline" "$pattern" ; then
      message "Keyword '$keyword_alias' found in input stream."
      debug "Again returning with 0."
      return 0
    fi
    debug "Keyword '$keyword_alias' not found. (Return 1)"
    return 1
}

check_gen_keyword ()
{
    debug "Checking if the Gen keyword is set in the route section."
    # Assigning the gen option to the pattern
    local parseline="$1"
    local pattern="[Ge][Ee][Nn]"
    local keyword_alias="Gen"
    debug "Checking '$parseline' for pattern '$pattern'. Description: '$keyword_alias'."
    if check_any_keyword "$parseline" "$pattern" ; then
      message "Keyword '$keyword_alias' found in input stream."
      debug "Again returning with 0."
      return 0
    fi
    debug "Keyword '$keyword_alias' not found. (Return 1)"
    return 1
}

check_opt_keyword ()
{
    debug "Checking if the Opt keyword is set in the route section."
    # Assigning the opt option to the pattern
    local parseline="$1"
    local pattern="[Oo][Pp][Tt]"
    local keyword_alias="Opt"
    debug "Checking '$parseline' for pattern '$pattern'. Description: '$keyword_alias'."
    if check_any_keyword "$parseline" "$pattern" ; then
      message "Keyword '$keyword_alias' found in input stream."
      debug "Again returning with 0."
      return 0
    fi
    debug "Keyword '$keyword_alias' not found. (Return 1)"
    return 1
}

validate_g16_route ()
{
    local read_route="$1"
    local g16_output
    debug "Read the following route section:"
    debug "$read_route"
    if [[ -z $read_route ]] ; then 
      warning "Route section appears to be empty."
      warning "Check if there is an actual route card '#(|N|P|T)' in the input."
    else
      debug "Found route card and will process."
    fi 
    if g16_output=$($g16_testrt_cmd "$read_route" 2>&1) ; then
      message "Route section has no syntax errors."
      debug "$g16_output"
    else
      warning "There was an error in the route section"
      message "$g16_output"
      return 1
    fi
}

#
# modified input files
#

extract_jobname_inoutnames ()
{
    # Assigns the global variables inputfile outputfile jobname
    # Checks is locations are read/writeable
    local testfile="$1"
    local input_suffix output_suffix
    local -a test_possible_inputfiles
    debug "Validating: $testfile"

    # Check if supplied inputfile is readable, extract suffix and title
    if inputfile=$(is_readable_file_or_exit "$testfile") ; then
      jobname="${inputfile%.*}"
      input_suffix="${inputfile##*.}"
      debug "Jobname: $jobname; Input suffix: $input_suffix."
      # Assign matching outputfile
      if output_suffix=$(match_output_suffix "$input_suffix") ; then
        debug "Output suffix: $output_suffix."
      else
        # Abort when input-suffix cannot be identified
        fatal "Unrecognised suffix of inputfile '$testfile'."
      fi
    else
      # Assume that only jobname was given
      debug "Assuming that '$testfile' is the jobname."
      jobname="$testfile"
      unset testfile
      mapfile -t test_possible_inputfiles < <( ls ./"$jobname".* 2> /dev/null ) 
      debug "Found possible inputfiles: ${test_possible_inputfiles[*]}"
      (( ${#test_possible_inputfiles[*]} == 0 )) &&  fatal "No input files belonging to '$jobname' found in this directory."
      for testfile in "${test_possible_inputfiles[@]}" ; do
        input_suffix="${testfile##*.}"
        debug "Extracted input suffix '$input_suffix', and will test if allowed."
        if output_suffix=$(match_output_suffix "$input_suffix") ; then
          debug "Will use input suffix '$input_suffix'."
          debug "Will use output suffix '$output_suffix'."
          break
        fi
      done
      debug "Jobname: $jobname; Input suffix: $input_suffix; Output suffix: $output_suffix."
    fi
    outputfile="$jobname.$output_suffix"
}

validate_write_in_out_jobname ()
{
    # Assigns the global variables inputfile outputfile jobname
    # Checks is locations are read/writeable
    local testfile="$1"
    extract_jobname_inoutnames "$testfile"

    # Check special ending of input file
    # it is only necessary to check agains one specific suffix 'gjf' as that is hard coded in main script
    if [[ "${inputfile##*}" == "gjf" ]] ; then
      warning "The chosen inputfile will be overwritten."
      backup_file "$inputfile" "${inputfile}.bak"
      inputfile="${inputfile}.bak"
    fi

    # Check if an outputfile exists and prevent overwriting
    backup_if_exists "$outputfile"

    # Display short logging message
    message "Will process Inputfile '$inputfile'."
    message "Output will be written to '$outputfile'."
}

write_g16_input_file ()
{
    debug "Writing new (modified) input file."
    local verified_checkpoint verified_old_checkpoint
    # checkpoint is a global variable
    if [[ ! -z $old_checkpoint ]] ; then
      if verified_old_checkpoint=$(test_file_location "$old_checkpoint") ; then
        debug "verified_old_checkpoint=$verified_old_checkpoint"
        warning "Checkpoint file '$old_checkpoint' does not exist."
        warning "Gaussian will likely fail to run this calculation."
      else
        debug "Found checkpoint file."
      fi
      echo "%OldChk=$old_checkpoint"
    fi
    [[ -z $checkpoint ]] && checkpoint="${jobname}.chk"
    if verified_checkpoint=$(test_file_location "$checkpoint") ; then
      message "Checkpoint file '$checkpoint' does not exists and will be created."
      debug "verified_checkpoint=$verified_checkpoint"
      echo "%Chk=$verified_checkpoint"
    else
      warning "Checkpoint file '$checkpoint' exists and will very likely be overwritten."
      warning "This may lead to an unusable file and loss of data."
      message "If you are attempting to read in data from a previous run, use"
      message "the directive '%OldChk=<previous_calculation>' instead."
      echo "%Chk=$checkpoint"
    fi
    if [[ "$g16_checkpoint_save" == "false" ]] ; then
      message "Named checkpoint files will not be saved."
      echo "%NoSave"
    fi
    # requested_numCPU is a global variable
    echo "%NProcShared=$requested_numCPU"
    # requested_memory is a global variable
    echo "%Mem=${requested_memory}MB"
    debug "Number of additional link0 commands: ${#inputfile_link0[@]}"
    debug "Elements: ${inputfile_link0[*]}"
    # Add all remaining and stored link0 directives
    (( ${#inputfile_link0[@]} > 0 )) && printf "%s\\n" "${inputfile_link0[@]}"

    local use_route_section
    # requested_maxdisk is a global variable
    [[ -z $requested_maxdisk ]] && fatal "Value for keyword 'MaxDisk' is unset, probably compromised rc."
    # Remove any existing MaxDisk keyword to add one with script value.
    while ! route_section=$(remove_maxdisk_keyword "$route_section") ; do : ; done
    use_route_section=$(collate_route_keywords "$route_section MaxDisk=${requested_maxdisk}MB")
    message "Added 'MaxDisk=${requested_maxdisk}MB' to the route section."
    # Fold the route section to 80 characters for better readability
    fold -w80 -c -s <<< "$use_route_section"
    # A blank line terminates the route section
    echo ""

    if [[ ! -z $title_section ]] ; then
      # Fold the title section to 80 characters for better readability
      fold -w80 -c -s <<< "$title_section"
      # A blank line terminates the title section
      echo ""
      [[ -z $molecule_charge ]] && fatal "Charge unset; somewhere, something went wrong."
      [[ -z $molecule_mult ]] && fatal "Multiplicity unset; somewhere, something went wrong."
      # After the charge and multiplicity the molecule specification is entered
      if [[ -z $molecule_fragments ]] ; then
        echo "$molecule_charge   $molecule_mult"
      else
        echo "$molecule_charge, $molecule_mult    $molecule_fragments"
      fi
    fi

    # Append the rest of the input file
    debug "Lines till end of file: ${#inputfile_body[@]}"
    debug "Content:"
    debug "$(printf '%s\n' "${inputfile_body[@]}")"
    printf "%s\\n" "${inputfile_body[@]}"
    if (( ${#use_custom_tail[*]} > 0 )) ; then
      debug "Additional lines for input: ${#use_custom_tail[@]}"
      debug "Content: ${use_custom_tail[*]}"
      printf "%s\\n" "${use_custom_tail[@]}"
    fi
    # The input file must be terminated by a blank line
    echo ""
    # Add some information about the creation of the script
    echo "!Automagically created with $scriptname ($softwarename, $version, $versiondate)"
    echo "!$script_invocation_spell"
    #echo "!${script_invocation_spell/#$HOME/<HOME>}"
}



