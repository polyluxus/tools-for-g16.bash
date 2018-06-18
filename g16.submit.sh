#! /bin/bash

# Gaussian 16 submission script
#
# You might not want to make modifications here.
# If you do improve it, I would be happy to learn about it.
#

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This is $scriptname!
#hlp
#hlp   It will sumbit a gaussian input file to the queueing system.
#hlp   It is designed to work on the RWTH compute cluster in 
#hlp   combination with the bsub queue.
#hlp
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp
#hlp   VERSION    :   $version
#hlp   DATE       :   $versiondate
#hlp
#hlp   USAGE      :   $scriptname [options] [IPUT_FILE]
#hlp

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


#
# Test if a given value is an integer
#

is_integer()
{
    [[ $1 =~ ^[[:digit:]]+$ ]]
}

validate_integer () 
{
    if ! is_integer "$1"; then
        [ ! -z "$2" ] && fatal "Value for $2 ($1) is no integer."
          [ -z "$2" ] && fatal "Value \"$1\" is no integer."
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
# Routines for parsing the supplied input file
#

parse_link0 ()
{
    #link0 directives are before the route section
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
    local rematch_index=1
    debug "Testing for checkpoint file."
    checkpoint=$(parse_link0 "$parseline" "$pattern" "$rematch_index") || return 1
    debug "Checkpoint file is '$checkpoint'"
}

warn_nprocs_directive ()
{
    local parseline="$1"
    local pattern="^[[:space:]]*%[Nn][Pp][Rr][Oo][Cc][Ss][Hh][Aa][Rr][Ee][Dd]=([^[:space:]]+)([[:space:]]+|$)"
    local rematch_index=0
    local nprocs_read
    debug "Testing for NProcShared."

    if nprocs_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") ; then
      warning "Link0 directive '$nprocs_read' will be substituted with script settings."
      return 0
    else
      debug "Not a NProcShared statement."
      return 1
    fi
}

warn_mem_directive ()
{
    local parseline="$1"
    local pattern="^[[:space:]]*%[Mm][Ee][Mm]=([^[:space:]]+)([[:space:]]+|$)"
    local rematch_index=0
    local memory_read
    debug "Testing for memory."

    if memory_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") ; then 
      warning "Link0 directive '$memory_read' will be substituted with script settings."
      return 0
    else
      debug "Not a memory statement."
      return 1
    fi
}

# other link0 derectives may be appended here

remove_comment ()
{
    debug "Attempting to remove comment."
    local parseline="$1"
    debug "Parsing: '$parseline'"
    local pattern="^[[:space:]]*([^!]+)[!]*[[:space:]]*(.*)$"
    if [[ $parseline =~ $pattern ]] ; then
      debug "Matched: ${BASH_REMATCH[0]}"
      # Return the line without the comment part
      echo "${BASH_REMATCH[1]}"
      [[ ! -z ${BASH_REMATCH[2]} ]] && message "Removed comment: ${BASH_REMATCH[2]}"
      debug "Return 0."
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

# check for AllCheck because then we have to omit title and multiplicity
check_allcheck_option ()
{   
    debug "Checking if we can skip reading title, charge, and multiplicity."
    local parseline="$1"
    local pattern="[Aa][Ll][Ll][Cc][Hh][Ee][Cc][Kk]"
    if [[ $parseline =~ $pattern ]] ; then
      message "Found 'AllCheck', skipping reading title, charge, and multiplicity."
      debug "Return 0."
      return 0
    fi
    debug "Title, charge, and multiplicity need to be read. (Return 1)"
    return 1
}

# Parsing happens now

read_inputfile ()
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
    local parsefile="$1" line appendline pattern
    debug "Working on: $parsefile"
    # The hash marks the beginning of the route
    local route_start_pattern="^[[:space:]]*#[nNpPtT]?([[:space:]]|$)"
    # We need to store link0 as an array
    local store_link0=1 link0_index=0 link0_temp
    # Flags when to read what
    local store_route=0 store_title=0 store_charge_mult=0 
    # The remainder aslo goes into an array
    local body_index=0

    while read -r line; do
      debug "Read line: $line"
      if (( store_link0 == 1 )) ; then
        line=$(remove_comment "$line") || fatal "There appears to be a blank line in Link0. Abort."
        # There is only one directive per line
        if [[ -z $checkpoint ]] ; then
          get_chk_file "$line" && continue
        fi
        warn_nprocs_directive "$line" && continue
        warn_mem_directive "$line" && continue
        pattern="^[[:space:]]*%(.+)=([^[:space:]]+)([[:space:]]+|$)"
        if link0_temp=$(parse_link0 "$line" "$pattern" "0") ; then
          link0[$link0_index]="$link0_temp"
          (( link0_index++ ))
          continue
        else
          store_link0=2
        fi
      fi
      if (( store_route == 0 )) ; then
        if [[ $line =~ $route_start_pattern ]] ; then
          debug "Start reading route section."
          # Start reading the route section end reading link0 directives
          store_route=1
          store_link0=2
          route_section=$(remove_comment "$line")
          # Read next line
          continue
        fi
      fi
      if (( store_route == 1 )) ; then
        debug "Reading route section."
        # Still reading the route section
        if [[ $line =~ ^[[:space:]]*$ ]]; then
          # End reading route when blank line is encountered
          # and start reading the title
          store_title=1
          store_route=2
          debug "Finished route section."
          if check_allcheck_option "$route_section" ; then
            store_title=2
            store_charge_mult=2
          fi
          continue
        fi
        appendline=$(remove_comment "$line") 
        # there might be comment only lines which can be removed
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
          continue
        fi
        # The title section is free form
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
        appendline=$(remove_comment "$line") 
        pattern="^[[:space:]]*([+-]?[0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$"
        if [[ $appendline =~ $pattern ]] ; then
          molecule_charge="${BASH_REMATCH[1]}"
          molecule_mult="${BASH_REMATCH[2]}"
        fi
        debug "Finished reading charge ($molecule_charge) and multiplicity ($molecule_mult)."
        store_charge_mult=2
        # Next should be geometry and stuff
        continue
      fi
      
      debug "Reading rest of input file."
      if line=$(remove_comment "$line") ; then
        debug "Checking line '$line' is empty after removing comment."
        # If after removing the comment the line is empty, skip to the next line
        [[ $line =~ ^[[:space:]]*$ ]] && continue
        debug "Line will be kept."
      fi

      inputfile_body[$body_index]="$line" 
      debug "Read and stored: ${inputfile_body[$body_index]}"
      (( body_index++ ))
      debug "Increase index to $body_index."

    done < "$parsefile"
    debug "Finished reading input file."
}

collate_keyword_opts ()
{
    # The function takes an inputstring and removes any unnecessary spaces
    # needed for collate_keywords
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

collate_keywords ()
{
    # This function removes spaces which have been entered in the original input
    # so that the folding (to 80 characters) doesn't break a keyword.
    debug "Entering collate_keywords."
    local inputstring="$1"
    debug "Input: $inputstring"
    # The collated section will be saved to
    local keepstring
    # If we encounter a long keyword stack, we need to set a different returncode
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
        keep_options=$(collate_keyword_opts "$keep_options")

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

validate_write_in_out_jobname ()
{
    # Assigns the global variables inputfile outputfile jobname
    # Checks is locations are read/writeable
    local allowed_input_suffix=(com in inp gjf COM IN INP GJF)
    local match_output_suffix=(log out log log LOG OUT LOG LOG)
    local input_suffix output_suffix
    local choices=${#allowed_input_suffix[*]} count
    local testfile="$1"
    debug "Validating: $testfile"

    # Check if supplied inputfile is readable, extract suffix and title
    if inputfile=$(is_readable_file_or_exit "$testfile") ; then
      jobname="${inputfile%.*}"
      input_suffix="${inputfile##*.}"
      debug "Jobname: $jobname; Input suffix: $input_suffix."
      # Assign matching outputfile
      for ((count=0; count<choices; count++)) ; do
        if [[ "$input_suffix" == "${allowed_input_suffix[$count]}" ]]; then
          output_suffix="${match_output_suffix[$count]}"
          debug "Output suffix: $output_suffix."
          break
        fi
      done
      # Abort when input-suffix cannot be identified
      if [[ -z $output_suffix ]] ; then
          fatal "Unrecognised suffix of inputfile '$testfile'."
      fi
    else
      # Check if only the jobtitle was given
      for ((count=0; count<choices; count++)); do
        if inputfile=$(is_readable_file_or_exit "$testfile.${allowed_input_suffix[$count]}") ; then
          jobname="$testfile"
          input_suffix="${allowed_input_suffix[$count]}"
          output_suffix="${match_output_suffix[$count]}"
          debug "Jobname: $jobname; Input suffix: $input_suffix; Output suffix: $output_suffix."
          break
        fi
      done
      # Abort if no suitable inputfile was found
      if [[ -z $input_suffix ]] ; then
          fatal "Unable to access '$testfile'."
      fi
    fi

    # Check special ending of input file
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

#
# Functions to modify the route section
#

remove_any_keyword ()
{
    # Takes in a string (the route section) and 
    local test_line="$1"
    # removes the pattern (keyword) if present and 
    local test_pattern="$2"
    # returns the result.
    local return_line
    # Since spaces have been removed form within the keywords previously with collate_keywords, 
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
    # Assigns the opt keyword to the pattern
    local test_routesection="$1"
    local pattern
    pattern="[Mm][Aa][Xx][Dd][Ii][Ss][Kk]"
    remove_any_keyword "$test_routesection" "$pattern" || return 1
}

# Others (?)

write_new_inputfile ()
{
    local verified_checkpoint
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
    echo "%NProcShared=$requested_numCPU"
    echo "%Mem=${requested_memory}MB"
    debug "Number of additional link0 commands: ${#link0[@]}"
    debug "Elements: ${link0[*]}"
    (( ${#link0[@]} > 0 )) && printf "%s\\n" "${link0[@]}"

    local use_route_section
    [[ -z $requested_maxdisk ]] && fatal "Keyword 'MaxDisk' is unset, probably compromised rc."
    while ! route_section=$(remove_maxdisk "$route_section") ; do : ; done
    use_route_section=$(collate_keywords "$route_section MaxDisk=${requested_maxdisk}MB")
    fold -w80 -c -s <<< "$use_route_section"
    echo ""

    if [[ ! -z $title_section ]] ; then
      fold -w80 -c -s <<< "$title_section"
      echo ""
      [[ -z $molecule_charge ]] && fatal "Charge unset; somewhere, something went wrong."
      [[ -z $molecule_mult ]] && fatal "Multiplicity unset; somewhere, something went wrong."
      echo "$molecule_charge   $molecule_mult"
    fi

    debug "Lines till end of file: ${#inputfile_body[@]}"
    debug "Content: ${inputfile_body[*]}"
    printf "%s\\n" "${inputfile_body[@]}"
    echo ""
    echo "!Automagically created with $scriptname"
    echo "!$script_invocation_spell"
}


process_inputfile ()
{
    local testfile="$1"
    debug "Processing Input: $testfile"
    validate_write_in_out_jobname "$testfile"
    debug "Jobname: $jobname; Input: $inputfile; Output: $outputfile."

    read_inputfile "$inputfile"
    inputfile_modified="$jobname.gjf"
    backup_if_exists "$inputfile_modified"
    debug "Writing new input: $inputfile_modified"

    write_new_inputfile > "$inputfile_modified"
    message "Written modified inputfile '$inputfile_modified'."
}








#
# Routine(s) for writing the submission script
#

write_jobscript ()
{
    debug "Creating a job script."
    local queue="$1" queue_short 
    [[ -z $queue ]] && fatal "No queueing systen selected. Abort."
    queue_short="${queue%-*}"
    submitscript="${jobname}.${queue_short}.bash"
    debug "Selected queue: $queue; short: $queue_short"
    debug "Will write submitscript to: $submitscript"

    if [[ -e $submitscript ]] ; then
      warning "Designated submitscript '$submitscript' already exists."
      warning "File will be overwritten."
      # Backup or delete, or overwrite?
    fi
    [[ -z $inputfile_modified ]]   && fatal "No inputfile specified. Abort."
    [[ -z $outputfile ]]  && fatal "No outputfile selected. Abort."

    # Open file descriptor 9 for writing
    exec 9> "$submitscript"

    local scale_memory_percent overhead_memory
    # Add one more process, and give Gaussian some more space (define in rc / top of script)
    scale_memory_percent=$(( 100 * ( requested_numCPU + 1 ) / requested_numCPU ))
    debug "Scaling memory by $scale_memory_percent% (requested_numCPU=$requested_numCPU)."
    overhead_memory=$(( requested_memory * scale_memory_percent / 100 + g16_overhead ))
    debug "requested_memory=$requested_memory; g16_overhead=$g16_overhead"
    message "Request a total memory of $overhead_memory MB, including overhead for Gaussian."

    # Header is different for the queueing systems
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      echo "#!/bin/bash" >&9
      echo "# Submission script automatically created with $scriptname" >&9

      cat >&9 <<-EOF
			#PBS -l nodes=1:ppn=$requested_numCPU
			#PBS -l mem=${overhead_memory}m
			#PBS -l walltime=$requested_walltime
			#PBS -N ${jobname}
			#PBS -m ae
			#PBS -o $submitscript.o\${PBS_JOBID%%.*}
			#PBS -e $submitscript.e\${PBS_JOBID%%.*}
			EOF
      if [[ ! -z $dependency ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' 
        # which should be recognised by PBS
        echo "#PBS -W depend=afterok$dependency" >&9
      fi
      echo "jobid=\"\${PBS_JOBID%%.*}\"" >&9

    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      echo "#!/usr/bin/env bash" >&9
      echo "# Submission script automatically created with $scriptname" >&9

      cat >&9 <<-EOF
			#BSUB -n $requested_numCPU
			#BSUB -a openmp
			#BSUB -M $overhead_memory
			#BSUB -W ${requested_walltime%:*}
			#BSUB -J ${jobname}
			#BSUB -N 
			#BSUB -o $submitscript.o%J
			#BSUB -e $submitscript.e%J
			EOF
      if [[ ! -z $dependency ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' (PBS)
        # and needs to be transformed to LSF compatible format
        debug "Resolving dependencies from '$dependency'"
        local resolve_dependency remove_dependency
        while [[ $dependency: =~ :([[:digit:]]+): ]]; do
          if [[ -z $resolve_dependency ]] ; then
            resolve_dependency="done(${BASH_REMATCH[1]})"
            remove_dependency=":${BASH_REMATCH[1]}"
            dependency="${dependency/$remove_dependency}"
          else
            resolve_dependency="$resolve_dependency && done(${BASH_REMATCH[1]})"
            remove_dependency=":${BASH_REMATCH[1]}"
            dependency="${dependency/$remove_dependency}"
          fi
        done
        echo "#BSUB -w \"$resolve_dependency\"" >&9
      fi
      if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
        echo "#BSUB -R select[hpcwork]" >&9
      fi
      if [[ "$bsub_project" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        message "No project selected."
      else
        echo "#BSUB -P $bsub_project" >&9
      fi
      echo "jobid=\"\${LSB_JOBID}\"" >&9

    else
      fatal "Unrecognised queueing system '$queue'."
    fi

    echo "" >&9

    # How Gaussian is loaded
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      cat >&9 <<-EOF
			g16root="$g16_installpath"
			export g16root
			. \$g16root/g16/bsd/g16.profile
			EOF
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      (( ${#g16_modules[*]} == 0 )) && fatal "No modules to load."
      cat >&9 <<-EOF
      # Might only be necessary for rwth (?)
			source /usr/local_host/etc/init_modules.sh
			module load ${g16_modules[*]} 2>&1
			# Because otherwise it would go to the error output.
			
			EOF
    fi

    # NBO6 ?

    # Some of the body is the same for all queues (so far)
    cat >&9 <<-EOF
		# Get some information o the platform
		echo "This is \$(uname -n)"
		echo "OS \$(uname -o) (\$(uname -p))"
		echo "Running on $requested_numCPU \
		      \$(grep 'model name' /proc/cpuinfo|uniq|cut -d ':' -f 2)."
		echo "Calculation $inputfile_modified from $PWD."
		echo "Working directry is $PWD"
		
		cd "$PWD" || exit 1
		
		# Make a new scratch directory
		g16_subscratch="$g16_scratch/g16job\$jobid"
		mkdir -p "\$g16_subscratch"
		export GAUSS_SCRDIR="\$g16_subscratch"
		
		EOF

    # Insert additional environment variables
    if [[ ! -z "$manual_env_var" ]]; then
      echo "export $manual_env_var" >&9
      debug "export $manual_env_var"
    fi

    cat >&9 <<-EOF
		echo -n "Start: "
		date
		g16 < "$inputfile_modified" > "$outputfile"
		joberror=\$?
		
		echo "Looking for files with filesize zero and delete them in '\$g16_subscratch'."
		find "\$g16_subscratch" -type f -size 0 -exec rm -v {} \\;
		echo "Deleting scratch '\$g16_subscratch' if empty."
		find "\$g16_subscratch" -maxdepth 0 -empty -exec rmdir -v {} \\;
		[[ -e "\$g16_subscratch" ]] && mv -v "\$g16_subscratch" "$PWD/${jobname}.scr\$jobid"
		echo -n "End  : "
		date
		exit \$joberror
		EOF

    # Close file descriptor
    exec 9>&-
    message "Written submission script '$submitscript'."
    return 0
}

submit_jobscript_hold ()
{
    local queue="$1" submit_id
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      submit_id="$(qsub -h "$submitscript")" || exit_status="$?"
      message "Submitted as $submit_id."
      message "Use 'qrls $submit_id' to release the job."
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      submit_id="$(bsub -H < "$submitscript" 2>&1 )" || exit_status="$?"
      message "$submit_id"
    fi
}

submit_jobscript_keep ()
{
    local queue="$1" 
    message "Created submit script, use"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      message "  qsub $submitscript"
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      message "  bsub < $submitscript"
    fi
    message "to start the job."
}

submit_jobscript_run  ()
{
    local queue="$1" submit_message
    debug "queue=$queue; submitscript=$submitscript"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      submit_message="Submitted as $(qsub "$submitscript")" || exit_status="$?"
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      submit_message="$(bsub < "$submitscript" 2>&1 )" || exit_status="$?"
      submit_message="${submit_message#Info: }"
    else
      fatal "Unrecognised queueing system '$queue'."
    fi
    if (( exit_status > 0 )) ; then
      warning "Submission went wrong."
      debug "$submit_message"
    else
      message "$submit_message"
    fi
    return $exit_status
}

submit_jobscript ()
{
    local queue="$1" submit_status="$2" 
    debug "queue=$queue; submit_status=$submit_status"
    case "$submit_status" in
    
      [Hh][Oo][Ll][Dd]) 
        submit_jobscript_hold "$queue" || return $?
        ;;
    
      [Kk][Ee][Ee][Pp]) 
        submit_jobscript_keep "$queue" || return $?
        ;;
    
      [Rr][Uu][Nn])
        submit_jobscript_run "$queue" || return $?
        ;;
    
      *)  
        fatal "Unrecognised status '$submit_status' requested for the job."
        ;;

    esac
}


#
# Process Options
#

process_options ()
{
  ##Needs complete rework

    #hlp   OPTIONS    :
    #hlp    
    local OPTIND=1 

    while getopts :m:p:d:w:b:e:j:Hkq:Q:P:sh options ; do
        case $options in

          #hlp     -m <ARG> Define the total memory to be used in megabyte.
          #hlp              The total request will be larger to account for 
          #hlp              overhead which Gaussian may need. (Default: 512)
          #hlp
            m) 
               validate_integer "$OPTARG" "the memory"
               if (( OPTARG == 0 )) ; then
                 fatal "Memory limit must not be zero."
               fi
               requested_memory="$OPTARG" 
               ;;

          #hlp     -p <ARG> Define number of professors to be used. (Default: 4)
          #hlp
            p) 
               validate_integer "$OPTARG" "the number of threads"
               if (( OPTARG == 0 )) ; then
                 fatal "Number of threads must not be zero."
               fi
               requested_numCPU="$OPTARG" 
               ;;

          #hlp     -d <ARG> Define disksize via the MaxDisk keyword (MB).
          #hlp              This option does not set a parameter for the queueing system,
          #hlp              but will only modify the input file with the size specification.
          #hlp              
            d) 
               validate_integer "$OPTARG" "the 'MaxDisk' keyword"
               if (( OPTARG == 0 )) ; then
                 fatal "The keyword 'MaxDisk' must not be zero."
               fi
               requested_maxdisk="$OPTARG"
               ;;

          #hlp     -w <ARG> Define maximum walltime.
          #hlp                Format: [[HH:]MM:]SS (Default: $requested_walltime)
          #hlp
            w) requested_walltime=$(format_duration_or_exit "$OPTARG")
               ;;

          #hlp     -b <ARG> Specify binary --TODO--
          #hlp
            b) warning "The binary specification is still in developement." ;;

          #hlp     -e <ARG> Specify environment variable to be passed on.
          #hlp              Input should have the form 'VARIABLE=<value>'.
          #hlp                (No sanity check will be performed, 
          #hlp                 may be specified multiple times.)
          #hlp
            e) 
               manual_env_var="$OPTARG $manual_env_var"
               ;;

          #hlp     -j <ARG> Wait for job with ID <ARG> (strictly numeric) to be done.
          #hlp              Option may be specified multiple times.
          #hlp              (BSUB) Implemented is only the use of the job ID.
          #hlp
            j) 
               validate_integer "$OPTARG" "the job ID"
               dependency="$dependency:$OPTARG"
               ;;

          #hlp     -H       submit the job with status hold (PBS) or PSUSP (BSUB)
          #hlp              --TODO--
          #hlp
            H) 
               requested_submit_status="hold"
               message "The submission with status 'hold' is still in development." 
               warning "(BSUB) Current settings would prevent releasing the job."
               ;;

          #hlp     -k       Only create (keep) the jobscript, do not submit it.
          #hlp
            k) 
               requested_submit_status="keep"
               ;;

          #hlp     -q       submit to queue --TODO--
          #hlp              
            q) warning "The submission to a specific queue is not yet possible." ;;

          #hlp     -Q <ARG> Which type of job script should be produced.
          #hlp              Arguments currently implemented: pbs-gen, bsub-rwth
          #hlp
            Q) request_qsys="$OPTARG" ;;

          #hlp     -P <ARG> Account to project.
          #hlp              Automatically selects '-Q bsub-rwth' and remote execution.
          #hlp
            P) 
               bsub_project="$OPTARG"
               request_qsys="bsub-rwth"  
               ;;

          #hlp     -s       Suppress logging messages of the script.
          #hlp              (May be specified multiple times.)
          #hlp
            s) (( stay_quiet++ )) ;;

          #hlp     -h       this help.
          #hlp
            h) helpme ;;

           \?) fatal "Invalid option: -$OPTARG." ;;

            :) fatal "Option -$OPTARG requires an argument." ;;

        esac
    done

    # Shift all variables processed to far
    shift $((OPTIND-1))

    if [[ -z "$1" ]] ; then 
      fatal "There is no inputfile specified"
    fi

    # If a filename is specified, it must exist, otherwise exit
    # different mode let's you only use the jobname
    #requested_inputfile=$(is_readable_file_or_exit "$1") || exit 1 
    requested_inputfile="$1"
    shift
    debug "Specified input: $requested_inputfile"

    # Issue a warning that the addidtional flag has no effect.
    warn_additional_args "$@"
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

# Evaluate Options

process_options "$@"
process_inputfile "$requested_inputfile"
write_jobscript "$request_qsys"
submit_jobscript "$request_qsys" "$requested_submit_status" 

#hlp   AUTHOR    : Martin
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
