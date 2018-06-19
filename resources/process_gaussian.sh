#!/bin/bash

# If this script is not sourced, return before executing anything
if (( ${#BASH_SOURCE[*]} == 1 )) ; then
  echo "This script is only meant to be sourced."
  exit 0
fi

match_output_suffix ()
{
  local   allowed_input_suffix=(com in  inp gjf COM IN  INP GJF)
  local matching_output_suffix=(log out log log LOG OUT LOG LOG)
  local choices=${#allowed_input_suffix[*]} count
  local test_suffix="$1" return_suffix
  debug "(${FUNCNAME[0]}) test_suffix=$test_suffix; choices=$choices"
  
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

find_energy ()
{
    local logfile="$1" logname
    logname=${logfile%.*}
    logname=${logname/\.\//}
    # Initiate variables necessary for parsing output
    local readline pattern functional energy cycles
    # Find match from the end of the file 
    # Ref: http://unix.stackexchange.com/q/112159/160000
    # This is the slowest part. 
    # If the calulation is a single point with a properties block it might 
    # perform slower than $(grep -m1 'SCF Done' $logfile | tail -n 1).
    readline=$(tac "$logfile" | grep -m1 'SCF Done')
    # Gaussian output has following format, trap important information:
    # Method, Energy, Cycles
    # Example taken from BP86/cc-pVTZ for water (H2O): 
    #  SCF Done:  E(RB-P86) =  -76.4006006969     A.U. after   10 cycles
    pattern="(E\\(.+\\)) = (.+) [aA]\\.[uU]\\.[^0-9]+([0-9]+) cycles"
    if [[ $readline =~ $pattern ]]
    then 
      functional="${BASH_REMATCH[1]}"
      energy="${BASH_REMATCH[2]}"
      cycles="${BASH_REMATCH[3]}"

      # Print the line, format it for table like structure
      printf '%-25s %-15s = %20s ( %6s )\n' "$logname" "$functional" "$energy" "$cycles"
    else
      printf '%-25s No energy statement found.\n' "${logfile%.*}"
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

warn_oldchk_directive ()
{
    # In some cases the OldChk needs to be removed, issue a warning, let the main script handle the rest.
    local parseline="$1"
    local pattern="^[[:space:]]*%[Oo][Ll][Dd][Cc][Hh][Kk]=([^[:space:]]+)([[:space:]]+|$)"
    # The whole match (line, index 0) needs to be returned
    local rematch_index=0 
    local oldchk_read
    debug "Testing for OldChk."
    if oldchk_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") ; then
      warning "Link0 directive '$oldchk_read' found."
      return 0
    else
      debug "Not an OldChk directive."
      return 1
    fi
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

#was remove_comment ()
remove_g16_input_comment ()
{
    debug "(${FUNCNAME[0]}) Attempting to remove comment."
    local parseline="$1"
    debug "Parsing: '$parseline'"
    local pattern="^[[:space:]]*([^!]+)[!]*[[:space:]]*(.*)$"
    if [[ $parseline =~ $pattern ]] ; then
      debug "Matched: ${BASH_REMATCH[0]}"
      # Return the line without the comment part
      echo "${BASH_REMATCH[1]}"
      [[ ! -z ${BASH_REMATCH[2]} ]] && message "Removed comment: ${BASH_REMATCH[2]}"
      debug "Comment removed. Return 0."
      return 0
    elif [[ $parseline =~ ^!(.*)$ ]] ; then
      message "Removed comment: ${BASH_REMATCH[1]}"
      debug "Return 0."
      return 0
    else
      debug "Line is blank. Return 1."
      return 1 # Return false if blank line
    fi
}

# Parsing happens now

#was read_inputfile ()
read_g16_input_file ()
{
    # The route section contains one or more lines.
    # It always starts with # folowed by a space or the various verbosity levels 
    # NPT (case insensitive). The route section is terminated by a blank line.
    # This must always be present. 
    # The next two entries may be present (but only together).
    # It is immediately followed by the title section, which can also consist of 
    # multiple lines made up of (almost) anything. It is also terminated by a blank line.
    # Following that is the charge and multiplicity.
    # After that come geometry and other input sections, we trust the user knows how to
    # specify these and read them as they are.

    debug "(${FUNCNAME[0]}) Reading input file."
    local parsefile="$1" line appendline pattern
    debug "Working on: $parsefile"
    # The hash marks the beginning of the route (everything before is link0)
    local route_start_pattern="^[[:space:]]*#[nNpPtT]?([[:space:]]|$)"
    # which will be stored in the global variable 'route_section'
    # We need to store link0 as an array, which is a global variable called 'inputfile_link0'
    local store_link0=1 link0_index=0 link0_temp
    # Flags when to read what
    local store_route=0 store_title=0 store_charge_mult=0 
    # content stored in global variables 'title_section', 'molecule_charge', 'molecule_mult'
    # The remainder of the inputfile also goes into an array, 
    # which is a global variable called 'inputfile_body'
    local body_index=0

    while read -r line; do
      debug "Read line: $line"
      if (( store_link0 == 1 )) ; then
        line=$(remove_g16_input_comment "$line") || fatal "There appears to be a blank line in Link0. Abort."
        # There is only one directive per line, there must not be a blank line
        if [[ -z $checkpoint ]] ; then
          # If the chk directive is found, check the next line
          get_chk_file "$line" && continue
        fi
        if warn_nprocs_directive "$line" ; then
          # If the nprocs directive is found a warning will be issued,
          # add that the directive will be ignored.
          warning "The statement will be replace by script values."
          # Skip to the next line if the statement was found.
          continue
        fi
        if warn_mem_directive "$line" ; then
          # If the mem directive is found a warning will be issued,
          # add that the directive will be ignored.
          warning "The statement will be replace by script values."
          # Skip to the next line if the statement was found.
          continue
        fi

        # Set the pattern to the form '%<directive>=<content>'
        pattern="^[[:space:]]*%([^=]+)=([^[:space:]]+)([[:space:]]+|$)"
        if link0_temp=$(parse_link0 "$line" "$pattern" "0") ; then
          # If anything is found, everything (rematch index 0) must be stored
          inputfile_link0[$link0_index]="$link0_temp"
          (( link0_index++ ))
          continue
        else
          # If the pattern is not found, the link0 directives are completed,
          # switch reading off.
          store_link0=2
        fi
      fi

      if (( store_route == 0 )) ; then
        if [[ $line =~ $route_start_pattern ]] ; then
          debug "Start reading route section."
          # Start reading the route section end reading link0 directives
          store_route=1
          route_section=$(remove_g16_input_comment "$line")
          # Read next line
          continue
        fi
      fi
      if (( store_route == 1 )) ; then
        debug "Still reading route section."
        # Still reading the route section
        if [[ $line =~ ^[[:space:]]*$ ]]; then
          # End reading route when blank line is encountered
          # and start reading the title
          store_title=1
          store_route=2
          debug "Finished route section."
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
        # Clean line from comments, store in 'appendline' buffer
        appendline=$(remove_g16_input_comment "$line") 
        # there might be comment only lines which can be removed/ ignored
        [[ ! -z $appendline ]] && route_section="$route_section $appendline"
        # prepare for next read (just to be sure)
        unset appendline
        # Read next line
        continue
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
      fi
      if (( store_charge_mult == 1 )) ; then
        debug "Reading charge and multiplicity."
        appendline=$(remove_g16_input_comment "$line") 
        # Change the pattern to the '<+/-><number> <number>' format
        pattern="^[[:space:]]*([+-]?[0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$"
        if [[ $appendline =~ $pattern ]] ; then
          molecule_charge="${BASH_REMATCH[1]}"
          molecule_mult="${BASH_REMATCH[2]}"
        fi
        debug "Finished reading charge ($molecule_charge) and multiplicity ($molecule_mult)."
        store_charge_mult=2
        # Next should be geometry and other stuff
        continue
      fi
      
      debug "Reading rest of input file."
      if line=$(remove_g16_input_comment "$line") ; then
        # Empty lines will be kept (because above will be false)
        debug "Checking line '$line' is empty after removing comment."
        # If _after_ removing the comment the line is empty, skip to the next line
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        debug "Line will be kept."
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

# was collate_keyword_opts ()
collate_route_keyword_opts ()
{
    # The function takes an inputstring and removes any unnecessary spaces
    # needed for collate_route_keywords
    debug "(${FUNCNAME[0]}) Collating keyword options."
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

# was collate_keywords ()
collate_route_keywords ()
{
    # This function removes spaces which have been entered in the original input
    # so that the folding (to 80 characters) doesn't break a keyword.
    debug "(${FUNCNAME[0]}) Collating keywords."
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
    # the following format: keyword=(option1,option2,…) [no spaces]
    # Exeptions to the above: temperature=500 and pressure=2, 
    # where the equals is the only accepted form.
    # This is probably because they can also be options to 'freq'.

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
      inputstring="${inputstring//${BASH_REMATCH[0]}/}"
      # Keep keword, options, and how it was terminated
      keep_keyword="${BASH_REMATCH[1]}"
      keep_options="${BASH_REMATCH[2]}"
      keep_terminate="${BASH_REMATCH[3]}"

      # Remove spaces from IOPs (only evil people use them there)
      if [[ $keep_keyword =~ ^[Ii][Oo][Pp]$ ]] ; then
        keep_keyword="$keep_keyword$keep_options"
        keep_keyword="${keep_keyword// /}"
        unset keep_options # unset to not run into next 'if'
      fi

      if [[ ! -z $keep_options ]] ; then 
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
    local extended_test_pattern="($test_pattern[^[:space:]]*)([[:space:]]+|$)"
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

remove_maxdisk ()
{
    # Assigns the maxdisk keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Mm][Aa][Xx][Dd][Ii][Ss][Kk]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

# Others (?)

# check for AllCheck because then we have to omit title and multiplicity
check_allcheck_option ()
{   
    debug "Checking if the AllCheck keyword is set in the route section."
    local parseline="$1"
    local pattern="[Aa][Ll][Ll][Cc][Hh][Ee][Cc][Kk]"
    if [[ $parseline =~ $pattern ]] ; then
      message "Found 'AllCheck' keyword."
      debug "Return 0."
      return 0
    fi
    debug "No 'AllCheck' keyword found. (Return 1)"
    return 1
}

#
# modified input files
#

# parts need to be replaced with standard function
validate_write_in_out_jobname ()
{
    # Assigns the global variables inputfile outputfile jobname
    # Checks is locations are read/writeable
    local allowed_input_suffix=(com in inp gjf COM IN INP GJF)
    local match_output_suffix=(log out log log LOG OUT LOG LOG)
    local choices=${#allowed_input_suffix[*]} count
    local testfile="$1"
    local input_suffix output_suffix
    local -a test_possible_inputfiles
    debug "(${FUNCNAME[0]}) Validating: $testfile"

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

    # Check special ending of input file
    # it is only necessary to check agains one specific suffix 'gjf' as that is hard coded in main script
    if [[ "$input_suffix" == "gjf" ]] ; then
      warning "The chosen inputfile will be overwritten."
      backup_file "$inputfile" "${inputfile}.bak"
      inputfile="${inputfile}.bak"
    fi

    # Check if an outputfile exists and prevent overwriting
    outputfile="$jobname.$output_suffix"
    backup_if_exists "$outputfile"

    # Display short logging message
    message "Will process Inputfile '$inputfile'."
    message "Output will be written to '$outputfile'."
}

#was write_new_inputfile ()
write_g16_input_file ()
{
    debug "(${FUNCNAME[0]}) Writing new (modified) input file."
    local verified_checkpoint
    # checkpoint is a global variable
    [[ -z $checkpoint ]] && checkpoint="${jobname}.chk"
    if verified_checkpoint=$(test_file_location "$checkpoint") ; then
      debug "verified_checkpoint=$verified_checkpoint"
      echo "%Chk=$verified_checkpoint"
    else
      warning "Checkpoint file '$checkpoint' exists and will very likely be overwritten."
      warning "This may lead to an unusable file and loss of data."
      message "If you are attempting to read in data from a previous run, use"
      message "the directive '%OldChk=<previous_calculation>' instead."
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
    while ! route_section=$(remove_maxdisk "$route_section") ; do : ; done
    use_route_section=$(collate_route_keywords "$route_section MaxDisk=${requested_maxdisk}MB")
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
      # After the charge and multiplicity the molecule specification i9s entered
      echo "$molecule_charge   $molecule_mult"
    fi

    # Append the rest of the input file
    debug "Lines till end of file: ${#inputfile_body[@]}"
    debug "Content: ${inputfile_body[*]}"
    printf "%s\\n" "${inputfile_body[@]}"
    # The input file must be terminated by a blank line
    echo ""
    # Add some information about the creation of the script
    echo "!Automagically created with $scriptname"
    echo "!$script_invocation_spell"
}



