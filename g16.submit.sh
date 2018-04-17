#! /bin/bash

# Gaussian 16 submission script
version="0.0.2"
versiondate="2018-04-17"

# The following two lines give the location of the installation.
# They can be set in the rc file, too.
# General path to the g16 directory (this should work on every system)
installpath_g16="/path/is/not/set"
# Define where scratch files shall be written to
g16_scratch="$TEMP"
# On the RWTH cluster gaussian is loaded via a module system,
# enter the name of the module here:
g16_module="gaussian/16.a03_bin"

#####
#
# The actual script begins here. 
# You might not want to make modifications here.
# If you do improve it, I would be happy to learn about it.
#

#
# Print some helping commands
# The lines are distributed throughout the script and grepped for
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

helpme ()
{
    local line
    local pattern="^[[:space:]]*#hlp[[:space:]]?(.*)?$"
    while read -r line; do
      [[ "$line" =~ $pattern ]] && eval "echo \"${BASH_REMATCH[1]}\""
    done < <(grep "#hlp" "$0")
    exit 0
}

#
# Print logging information and warnings nicely.
# If there is an unrecoverable error: display a message and exit.
#

message ()
{
    if (( stay_quiet <= 0 )) ; then
      echo "INFO   : " "$*" >&3
    else
      debug "(info   ) " "$*"
    fi
}

warning ()
{
    if (( stay_quiet <= 1 )) ; then
      echo "WARNING: " "$*" >&2
    else
      debug "(warning) " "$*"
    fi
    return 1
}

fatal ()
{
    if (( stay_quiet <= 2 )) ; then 
      echo "ERROR  : " "$*" >&2
    else
      debug "(error  ) " "$*"
    fi
    exit 1
}

debug ()
{
    echo "DEBUG  : " "$*" >&4
}    

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
# Get settings from configuration file
#

test_rc_file ()
{
  local test_runrc="$1"
  debug "Testing '$test_runrc' ..."
  if [[ -f "$test_runrc" && -r "$test_runrc" ]] ; then
    echo "$test_runrc"
    return 0
  else
    debug "... missing."
    return 1
  fi
}

get_rc ()
{
  local test_runrc_dir test_runrc_loc return_runrc_loc runrc_basename
  # The rc should have some similarity with the actual scriptname
  local runrc_basename="$scriptbasename" runrc_bundle="g16.tools"
  while [[ ! -z $1 ]] ; do
    test_runrc_dir="$1"
    shift
    if test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_basename}rc")" ; then
      return_runrc_loc="$test_runrc_loc" 
      debug "   (found) return_runrc_loc=$return_runrc_loc"
      continue
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_basename}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/.${runrc_bundle}rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    elif test_runrc_loc="$(test_rc_file "$test_runrc_dir/${runrc_bundle}.rc")" ; then 
      return_runrc_loc="$test_runrc_loc"
      debug "   (found) return_runrc_loc=$return_runrc_loc"
    fi
  done
  debug "(returned) return_runrc_loc=$return_runrc_loc"
  echo "$return_runrc_loc"
}

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
# Determine or validate outputfiles
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
      warning "File '$file_return' exists."
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
    backup_file "$1" "$move_target"
}

# We don't need that?
generate_outputfile_name ()
{
  local return_outfile_name="$1"
  if [[ -z "$return_outfile_name" ]] ; then
    debug "Nothing specified to base outputname on, will use '${scriptbasename}.out' instead."
    echo "${scriptbasename}.out"
  else
    debug "Will base outputname on '$return_outfile_name'."
    echo "${return_outfile_name%.*}.${scriptbasename}.out"
    debug "${return_outfile_name%.*}.${scriptbasename}.out"
  fi
}

# Maybe need that one
replace_line ()
{
    debug "Enter 'replace_line'."
    local search_pattern="$1"
    debug "search_pattern=$search_pattern"
    local replace_pattern="$2"
    debug "replace_pattern=$replace_pattern"
    local inputstring="$3"
    debug "inputstring=$inputstring"

    (( $# < 3 )) && fatal "Wrong internal call of replace function. Please report this bug."

    if [[ "$inputstring" =~ ^(.*)($search_pattern)(.+)$ ]] ; then
      debug "Found match: ${BASH_REMATCH[0]}"
      echo "${BASH_REMATCH[1]}$replace_pattern${BASH_REMATCH[3]}"
      debug "Leave 'replace_line' with 0."
      return 0
    else
      debug "No match found. Leave 'replace_line' with 1."
      return 1
    fi
}    

# 
# Routines for parsing the supplied input file
#

parse_link0 ()
{
    #Lin0 directives are before the route section
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

    nprocs_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") || return 1
    warning "Link0 directive '$nprocs_read' will be substituted with script settings."
}

warn_mem_directive ()
{
    local parseline="$1"
    local pattern="^[[:space:]]*%[Mm][Ee][Mm]=([^[:space:]]+)([[:space:]]+|$)"
    local rematch_index=0
    local memory_read
    debug "Testing for memory."

    memory_read=$(parse_link0 "$parseline" "$pattern" "$rematch_index") || return 1
    warning "Link0 directive '$memory_read' will be substituted with script settings."
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
      return 0
    elif [[ $parseline =~ ^!(.*)$ ]] ; then
      message "Removed comment: ${BASH_REMATCH[1]}"
      return 0
    else
      debug "Line is blank."
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
        pattern="^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]*$"
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
      line=$(remove_comment "$line") 
      inputfile_body[$body_index]="$line" 
      (( body_index++ ))

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
    echo "%Mem=$(( requested_numCPU * requested_memory ))MB"
    debug "Number of additional link0 commands: ${#link0[@]}"
    (( ${#link0[@]} > 0 )) && printf "%s\\n" "${link0[@]}"

    local use_route_section
    [[ -z $requested_maxdisk ]] && fatal "Keyword 'MaxDisk' is unset, probably compromised rc."
    use_route_section=$(collate_keywords "$route_section MaxDisk=${requested_maxdisk}MB")
    fold -w80 -c -s <<< "$use_route_section"
    echo ""

    if [[ ! -z $title_section ]] ; then
      fold -w80 -c -s <<< "$title_section"
      echo ""
      [[ -z $molecule_charge ]] && fatal "Charge unset; somewhere, something went wrong."
      [[ -z $molecule_mult ]] && fatal "Multiplicity unset; somewhere, something went wrong."
      echo "$molecule_charge   $molecule_mult"
      echo ""
    fi

    printf "%s\\n" "${inputfile_body[@]}"
    echo ""
    echo "!Automagically created with $scriptname"
}


process_inputfile ()
{
    local testfile="$1"
    debug "Processing Input: $testfile"
    validate_write_in_out_jobname "$testfile"
    debug "Jobname: $jobname; Input: $inputfile; Output: $outputfile."

    read_inputfile "$inputfile"
    backup_if_exists "$jobname.gjf"
    debug "Writing new input: $jobname.gjf"

    write_new_inputfile > "$jobname.gjf"
    message "Written modified inputfile '$jobname.gjf'."
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
    [[ -z $inputfile ]]   && fatal "No inputfile specified. Abort."
    [[ -z $outputfile ]]  && fatal "No outputfile selected. Abort."

    # Open file descriptor 9 for writing
    exec 9> "$submitscript"

    echo "#!/bin/bash" >&9
    echo "# Submission script automatically created with $scriptname" >&9

    local overhead_memory
    overhead_memory=$(( requested_memory + 400/requested_numCPU ))

    # Header is different for the queueing systems
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
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
        echo "#PBS -W depend=afterok$dependency" >&9
      fi
      echo "jobid=\"\${PBS_JOBID%%.*}\"" >&9

    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
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
        echo "#BSUB -w done($dependency)" >&9
      fi
      if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
        echo "#BSUB -R select[hpcwork]" >&9
      fi
      if [[ ! -z $bsub_rwth_project ]] ; then
        echo "#BSUB -P $bsub_rwth_project" >&9
      fi
      echo "jobid=\"\${LSF_JOBID}\"" >&9

    else
      fatal "Unrecognised queueing system '$queue'."
    fi

    # Some of the body is the same for all queues (so far)
    cat >&9 <<-EOF
		
		# Get some information o the platform
		echo "This is \$(uname -n)"
		echo "OS \$(uname -o) (\$(uname -p))"
		echo "Running on $requested_numCPU \
		      \$(grep 'model name' /proc/cpuinfo|uniq|cut -d ':' -f 2)."
		echo "Calculation $inputfile from $PWD."
		echo "Working directry is $PWD"
		
		cd "$PWD" || exit 1
		
		# Make a new scratch directory
		g16_subscratch="$g16_scratch/g16job\$jobid"
		mkdir -p "\$g16_subscratch"
		export GAUSS_SCRDIR="\$g16_subscratch"
		
		EOF

    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      cat >&9 <<-EOF
			g16root="$installpath_g16"
			export g16root
			. \$g16root/g16/bsd/g16.profile
			EOF
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      cat >&9 <<-EOF
			source /usr/local_host/etc/init_modules.sh
			module load CHEMISTRY 2>&1
			module load $g16_module 2>&1
      # Module writes info messages to error! (Why?)
			
			EOF
    fi

    # NBO6 ?

    # Insert additional environment variables
    if [[ ! -z "$manual_env_var" ]]; then
      echo "export $manual_env_var" >&9
      debug "export $manual_env_var"
    fi

    # Some of the body is the same for all queues (so far)
    cat >&9 <<-EOF
		echo -n "Start: "
		date
		g16 < "$inputfile" > "$outputfile"
		joberror=\$?
		
		echo "Looking for files with filesize zero and delete them."
		find "\$g16_subscratch" -type f -size 0 -exec rm -v {} \\;
		echo "Deleting scratch if empty."
		find "\$g16_subscratch" -maxdepth 0 -empty -exec rmdir -v {} \\;
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

          #hlp     -m <ARG> Define memory to be used per thread in megabyte.
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
            b) warning "The binary specification is still in developement." ;;

          #hlp     -e <ARG> Specify environment variable to be passed on
          #hlp                (No sanity check will be performed, 
          #hlp                 may be specified multiple times.)
            e) 
               manual_env_var="$OPTARG $manual_env_var"
               ;;

          #hlp     -j <ARG> Wait for <ARG> to be done. --TODO-- 
            j) 
               validate_integer "$OPTARG" "the job ID"
               dependency="$OPTARG"
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
               bsub_rwth_project="$OPTARG"
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
    requested_inputfile=$(is_readable_file_or_exit "$1") || exit 1 
    shift
    debug "Specified input: $requested_inputfile"

    # Issue a warning that the addidtional flag has no effect.
    warn_additional_args "$@"
}


#
# Begin main script
#

# Sent logging information to stdout
exec 3>&1

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

#
# Setting some defaults
#

# Print all information by default
stay_quiet=0

# Specify default Walltime, this is only relevant for remote
# execution as a header line for the queueing system
requested_walltime="24:00:00"

# Specify a default value for the memory
requested_memory=512

# This corresponds to  nthreads=<digit(s)> in the settings.ini
requested_numCPU=4

# The default which should be written to the inputfile
# regarding disk space
requested_maxdisk=10000

# Select a queueing system (pbs-gen/bsub-rwth)
request_qsys="pbs-gen"

# Account to project (only for rwth)
bsub_rwth_project=default

# Default operation should be to run (hold/keep)
requested_submit_status="run"

# Ensure that in/outputfile variables are empty
unset inputfile
unset outputfile

# Who are we and where are we?
scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
debug "Script is called '$scriptname'"
# remove scripting ending (if present)
scriptbasename=${scriptname%.sh} 
debug "Base name of the script is '$scriptbasename'"
scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
debug "Script is located in '$scriptpath'"

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
subg16_rc_loc="$(get_rc "$scriptpath" "/home/$USER" "$PWD")"
debug "subg16_rc_loc=$subg16_rc_loc"

# Load custom settings from the rc

if [[ ! -z $subg16_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-g16.bash/g16.tools.rc 
  . "$subg16_rc_loc"
  message "Configuration file '$subg16_rc_loc' applied."
else
  debug "No custom settings found."
fi

# Evaluate Options

process_options "$@"
process_inputfile "$requested_inputfile"
write_jobscript "$request_qsys"
submit_jobscript "$request_qsys" "$requested_submit_status" 

#hlp   AUTHOR    : Martin
message "Thank you for travelling with $scriptname ($version, $versiondate)."
exit 0

