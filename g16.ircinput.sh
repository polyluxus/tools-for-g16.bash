#! /bin/bash

# Gaussian 16 Input preparation script
#
# You might not want to make modifications here.
# If you do improve it, I would be happy to learn about it.
#

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This script reads an input file of a frequency calculation, 
#hlp   extracts the route section,
#hlp   and writes new input files for a IRC runs.
#hlp
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp
#hlp   Usage: $scriptname [options] [--] <INPUT_FILE>
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
    local error_count tmplog line
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
      debug "$(rm -v -- "$tmplog")"
      exit 1
    else
      debug "$(rm -v -- "$tmplog")"
    fi
}

#
# Specific functions for this script only
#

process_inputfile ()
{
    local testfile="$1"
    debug "Processing Input: $testfile"
    read_g16_input_file "$testfile"
    if [[ -z "$route_section" ]] ; then
      warning "It appears that '$testfile' does not contain a valid (or recognised) route section."
      warning "Make sure this template file contains '#/#P/#N/#T' followed by a space."
      return 1
    else
      debug "Route (unmodified): $route_section"
    fi
    local modified_route="$route_section"
    local -a additional_keywords

    extract_jobname_inoutnames "$testfile"
    
    # The opt and irc keywords are mutually exclusive, therefore opt needs to be removed
    while ! modified_route=$(remove_opt_keyword      "$modified_route") ; do : ; done
    # IRC calculations build upon Freq calculations, hence the latter should be present in the source
    if check_freq_keyword "$modified_route" ; then
      debug "Source input was frequency calculation."
    else
      warning "Keyword 'freq' was not found in input stream. Please check source input."
      warning "Running an IRC calculation makes only sense on a successful frequency calculation."
      warning "Please also check the created IRC inputfiles manually for errors."
    fi
    # remove the freq keyword, we don't need it anymore
    while ! modified_route=$(remove_freq_keyword     "$modified_route") ; do : ; done
    # The irc keyword will be added, therefore it should not be present
    while ! modified_route=$(remove_irc_keyword      "$modified_route") ; do : ; done
    # The guess/geom keyword will be added, it will clash if already present
    while ! modified_route=$(remove_guess_keyword    "$modified_route") ; do : ; done
    additional_keywords+=("guess(read)")
    message "Added '${additional_keywords[-1]}' to the route section."
    if check_allcheck_option "$modified_route" ; then 
      : 
    else 
      while ! modified_route=$(remove_geom_keyword     "$modified_route") ; do : ; done
      additional_keywords+=("geom(check)")
      message "Added '${additional_keywords[-1]}' to the route section."
    fi
    # Population analysis doesn't work well with irc runs
    while ! modified_route=$(remove_pop_keyword      "$modified_route") ; do : ; done
    # Writing additional output does not work well with irc runs
    while ! modified_route=$(remove_output_keyword   "$modified_route") ; do : ; done
    
    if modified_route=$(remove_gen_keyword "$modified_route") ; then
      debug "No gen keyword present."
    else
      warning "Additional basis set specifications have not been read,"
      warning "but will be retrieved from the checkpointfile."
      while ! modified_route=$(remove_gen_keyword "$modified_route") ; do : ; done
      additional_keywords+=('ChkBasis')
      message "Added '${additional_keywords[-1]}' to the route section."
      if check_denfit_keyword "$modified_route" ; then
        debug "No 'DenFit' present."
      else
        warning "Please check density fitting settings are compatible with 'ChkBasis'."
      fi
    fi

    # Add the custom route options
    if (( ${#use_custom_route_keywords[@]} == 0 )) ; then
      debug "No custom route keywords specified."
    else
      additional_keywords+=("${use_custom_route_keywords[@]}")
      debug "Added the following custom keywords to route section:"
      debug "$(fold -w80 -c -s <<< "${use_custom_route_keywords[*]}")"
    fi

    debug "Added the following keywords to route section:"
    debug "$(fold -w80 -c -s <<< "${additional_keywords[*]}")"

    # add the custom keywords
    modified_route="$modified_route ${additional_keywords[*]}"

    local verified_checkpoint
    if [[ -z $checkpoint ]] ; then
      checkpoint="${jobname}.chk"
      # Check if the guessed checkpointfile exists
      # (We'll trust the user if it was specified in the input file,
      #  after all the calculation might not be completed yet.)
      if verified_checkpoint=$(test_file_location "$checkpoint") ; then
        debug "verified_checkpoint=$verified_checkpoint"
        fatal "Cannot find '$verified_checkpoint'."
      else
        old_checkpoint="$checkpoint"
      fi
    else
      old_checkpoint="$checkpoint"
    fi

    # Throw away the body of the input file
    unset inputfile_body

    # declare a variable to hold the suffix
    local jobbasename use_file_suffix use_direction_suffix
    if [[ -n $inputfile_new ]] ; then
      jobbasename="${inputfile_new%.*}"
      use_file_suffix="${inputfile_new##*.}"
    else
      jobbasename="${jobname%.freq*}.irc"
      use_file_suffix="$g16_input_suffix"
    fi

    # create variables for irc keyword
    local concatenate_irc_opts irc_keyword

    if (( ${#use_irc_opts[@]} > 0 )) ; then
      concatenate_irc_opts=$(printf ',%s' "${use_irc_opts[@]}")
      concatenate_irc_opts=${concatenate_irc_opts:1}
    fi

    # Assign new checkpoint/inputfile in forward direction
    use_direction_suffix="fwd"
    jobname="${jobbasename}.$use_direction_suffix"
    checkpoint="${jobname}.chk"
    inputfile="${jobname}.$use_file_suffix"
    backup_if_exists "$inputfile"

    irc_keyword="IRC(RCFC,forward"
    [[ -n $concatenate_irc_opts ]] && irc_keyword+=",$concatenate_irc_opts"
    irc_keyword+=")"
    message "Added '$irc_keyword' to the route section."
    route_section="$modified_route $irc_keyword"

    write_g16_input_file > "$inputfile"
    message "Written modified inputfile '$inputfile'."
    unset irc_keyword

    # Assign new checkpoint/inputfile in reverse direction
    use_direction_suffix="rev"
    jobname="${jobbasename}.$use_direction_suffix"
    checkpoint="${jobname}.chk"
    inputfile="${jobname}.$use_file_suffix"
    backup_if_exists "$inputfile"

    irc_keyword="IRC(RCFC,reverse"
    [[ -n $concatenate_irc_opts ]] && irc_keyword+=",$concatenate_irc_opts"
    irc_keyword+=")"
    message "Added '$irc_keyword' to the route section."
    route_section="$modified_route $irc_keyword"

    write_g16_input_file > "$inputfile"
    message "Written modified inputfile '$inputfile'."
}

#
# Process Options
#

process_options ()
{
    #hlp   Options:
    #hlp    
    local OPTIND=1 

    while getopts :o:r:t:f:m:p:d:sh options ; do
        case $options in
          #hlp   -o <ARG>   Adds options <ARG> to the irc keyword.
          #hlp              May be specified multiple times.
          #hlp              The stack will be collated, but no sanity check will be performed.
          #hlp              Example Options: MaxPoints=<NUM>, StepSize=<NUM>, MaxCycle=<NUM>, ...
          #hlp
          o) 
            use_irc_opts+=("$OPTARG")
            ;;

          #hlp   -r <ARG>   Adds custom command <ARG> to the route section.
          #hlp              May be specified multiple times.
          #hlp              The stack will be collated, but no sanity check will be performed.
          #hlp 
          r) 
            use_custom_route_keywords+=("$OPTARG" )
            ;;

          #hlp   -t <ARG>   Adds <ARG> to the end (tail) of the new input file.
          #hlp              If specified multiple times, each argument goes to a new line.
          #hlp 
          t) 
            use_custom_tail[${#use_custom_tail[@]}]="$OPTARG" 
            ;;

          #hlp   -f <ARG>   Write inputfiles to <ARG>, where the argument should contain a dot,
          #hlp              e.g. the format like 'jobname.suffix' will produce two files
          #hlp              'jobname.fwd.suffix' and 'jobname.rev.suffix'.
          #hlp
          f)
            inputfile_new="$OPTARG"
            debug "Setting inputfile_new='$inputfile_new'."
            ;;

          # Link 0 related options
          #hlp   -m <ARG>   Define the total memory to be used in megabyte.
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

          #hlp   -p <ARG>   Define number of professors to be used. (Default: 4)
          #hlp
            p) 
               validate_integer "$OPTARG" "the number of threads"
               if (( OPTARG == 0 )) ; then
                 fatal "Number of threads must not be zero."
               fi
               requested_numCPU="$OPTARG" 
               ;;

          #hlp   -d <ARG>   Define disksize via the MaxDisk keyword (MB).
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

          #hlp   -s         Suppress logging messages of the script.
          #hlp              (May be specified multiple times.)
          #hlp
          s) 
            (( stay_quiet++ )) 
            ;;

          #hlp   -h         this help.
          #hlp
          h) 
            helpme 
            ;;

          #hlp     --       Close reading options.
          # This is the standard closing argument for getopts, it needs no implemenation.

          \?) 
            fatal "Invalid option: -$OPTARG." 
            ;;

          :) 
            fatal "Option -$OPTARG requires an argument." 
            ;;

        esac
    done

    # Shift all variables processed to far
    shift $((OPTIND-1))

    if [[ -z "$1" ]] ; then 
      fatal "There is no inputfile specified"
    fi

    # If a filename is specified, it must exist, otherwise exit
    # different mode let's you only use the jobname
    requested_inputfile=$(is_readable_file_or_exit "$1") || exit 1 
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
printf -v script_invocation_spell "'%s' " "${0/#$HOME/<HOME>}" "$@"

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

# Check whether we have the right numeric format (set it if not)
warn_and_set_locale

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
g16_tools_rc_searchlocations=( "$scriptpath" "$HOME" "$HOME/.config" "$PWD" )
g16_tools_rc_loc="$( get_rc "${g16_tools_rc_searchlocations[@]}" )"
debug "g16_tools_rc_loc=$g16_tools_rc_loc"

# Load custom settings from the rc

if [[ ! -z $g16_tools_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-g16.bash/g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '${g16_tools_rc_loc/*$HOME/<HOME>}' applied."
else
  debug "No custom settings found."
fi

# Initialise some variables

declare -a use_irc_opts
declare -a use_custom_route_keywords

# Evaluate Options

process_options "$@" || exit_status=$?
process_inputfile "$requested_inputfile" || exit_status=$?

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
exit $exit_status
