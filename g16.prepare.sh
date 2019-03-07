#! /bin/bash

# Gaussian 16 prepare script
#
# You might not want to make modifications here.
# If you do improve it, I would be happy to learn about it.
#

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This script reads an input file, extracts the geometry,
#hlp   and writes a new input file from default parameter.
#hlp
#hlp   Currently the script is able to handle files of the following format:
#hlp   xmol, Gaussian input with Cartesian coordinates,
#hlp   Turbomole coord format (and by extension xtb files)
#hlp
#hlp   This software comes with absolutely no warrenty. None. Nada.
#hlp
#hlp   Usage: $scriptname [options] [--] <IPUT_FILE>
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
    local testfile
    testfile=$(is_readable_file_or_exit "$1") || return 1
    debug "Processing Input: $testfile"
    read_xyz_geometry_file "$testfile" || return 1

    if [[ -z $jobname ]] ; then
      # Remove trailing directories
      jobname="${testfile##*/}"
      jobname="${jobname/..xyz/}"
    elif [[ "$jobname" == "%f" ]] ; then 
      # Remove trailing directories
      jobname="${testfile##*/}"
      jobname="${jobname/.xyz/}"
    elif [[ "$jobname" == "%s" ]] ; then 
      # Remove trailing directories
      jobname="${testfile##*/}"
      jobname="${jobname/.start.xyz/}"
    else
      debug "Jobname: $jobname"
    fi
    [[ -z $inputfile ]] && inputfile="${jobname}.$g16_input_suffix"
    checkpoint="${inputfile%.*}.chk"
   
    backup_if_exists "$inputfile"

    if [[ -z $route_section ]] ; then 
      route_section="$g16_route_section_default"
      warning "No route section was specified, using default:"
      warning "$(fold -w80 -c -s <<< "$route_section")"
    fi
    if [[ -z $use_temp_keyword ]] ; then
      debug "No temperature set."      
    else 
      route_section="$route_section $use_temp_keyword"
      message "Added '$use_temp_keyword' to route section."
    fi
    if [[ -z $use_pres_keyword ]] ; then 
      debug "No pressure set."
    else
      route_section="$route_section $use_pres_keyword"
      message "Added '$use_pres_keyword' to route section."
    fi
    if (( ${#use_custom_route_keywords[@]} == 0 )) ; then
      debug "No user specified keywords to be added."
    else
      route_section="$route_section ${use_custom_route_keywords[*]}"
      message "Added '${use_custom_route_keywords[*]}' to the route section."
    fi

    # Setting charge before substitutions 
    debug "Molecule charge: molecule_charge='$molecule_charge' molecule_set_charge='$molecule_set_charge'"
    # Check if it was set via the command line because that has precedence
    if [[ -n $molecule_set_charge ]] ; then
      # Assign the command line value if unset; it would be set from reading the input
      molecule_charge="${molecule_charge:-$molecule_set_charge}"
      # Check if values differ and issue a warning, assign commandline option
      if (( molecule_charge != molecule_set_charge )) ; then
        warning "The charge read from input file ($molecule_charge) will be overwritten with command line option ($molecule_set_charge)."
        molecule_charge="$molecule_set_charge"
      fi
    else
      # assign zero if unset
      molecule_charge="${molecule_charge:-0}"
    fi

    # Setting multiplicity before substitution
    debug "Molecule multiplicity: molecule_mult='$molecule_mult' molecule_set_mult='$molecule_set_mult'"
    # Check if it was set via the command line because that has precedence
    if [[ -n $molecule_set_mult ]] ; then
      # Assign the command line value if unset; it would be set from reading the input
      molecule_mult="${molecule_mult:-$molecule_set_mult}"
      # Check if values differ and issue a warning, assign commandline option
      if (( molecule_mult != molecule_set_mult )) ; then
        warning "The multiplicity read from input file ($molecule_mult) will be overwritten with command line option ($molecule_set_mult)."
        molecule_mult="$molecule_set_mult"
      fi
    else
      # assign one if unset
      molecule_mult="${molecule_mult:-1}"
    fi
    
    # Finish with a notification
    message "Setting charge ($molecule_charge) and multiplicity ($molecule_mult)."

    local substitute
    [[ -z $title_section ]] && title_section="Calculation: %j; %c; %M; %U; $(date +"%F %T (%Z)")"
    while [[ $title_section =~ ^(.*)(%.)(.*)$ ]] ; do
      case ${BASH_REMATCH[2]} in
        %f)   substitute="${testfile/.xyz}" ;;
        %F)   substitute="$testfile" ;;
        %s)   substitute="${testfile/start/}"
              substitute="${substitute/../.}" ;;
        %j)   substitute="$jobname" ;;
        %c)   substitute="chrg $molecule_charge" ;;
        %M)   substitute="mult $molecule_mult" ;;
        %U)   substitute="uhf $(( molecule_mult - 1 ))" ;;
         *)   warning "Removed unsupported substitution pattern '${BASH_REMATCH[2]}'." 
              # Remove from string to avoid looping
              substitute="" ;;
      esac
      title_section="${BASH_REMATCH[1]}$substitute${BASH_REMATCH[3]}"
      [[ -z $title_section ]] && title_section="Title card required"
    done
    message "Using caption '$title_section'."

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

    while getopts :T:P:r:R:l:t:C:j:f:c:M:U:m:p:d:sh options ; do
        case $options in
          #hlp   -T <ARG>   Specify temperature in kelvin.
          #hlp              Writes 'Temperature=<ARG>' to the route section. 
          #hlp              If specified multiple times, only the last one has an effect.
          #hlp 
          T)
            if is_float "$OPTARG" ; then
              use_temp_keyword="Temperature=$OPTARG"
            elif is_integer "$OPTARG" ; then
              use_temp_keyword="Temperature=${OPTARG}.0"
            else
              fatal "Value '$OPTARG' for the temperature is no (floating point) number."
            fi
            ;;

          #hlp   -P <ARG>   Specify pressure in atmosphere.
          #hlp              Writes 'Pressure=<ARG>' to the route section. 
          #hlp              If specified multiple times, only the last one has an effect.
          #hlp 
          P) 
            if is_float "$OPTARG" ; then
              use_pres_keyword="Pressure=$OPTARG"
            elif is_integer "$OPTARG" ; then
              use_pres_keyword="Pressure=${OPTARG}.0"
            else
              fatal "Value '$OPTARG' for the pressure is no (floating point) number."
            fi
            ;;

          #hlp   -r <ARG>   Adds custom command <ARG> to the route section.
          #hlp              May be specified multiple times.
          #hlp              The stack will be collated, but no sanity check will be performed.
          #hlp 
          r) 
            use_custom_route_keywords+=("$OPTARG")
            ;;

          #hlp   -R <ARG>   Specify the complete route section.
          #hlp              If specified multiple times, only the last has an effect.
          #hlp              This overwrites any previously specified route section.
          #hlp              This can be amended with other switches, like -r, -T, -P.
          #hlp 
          R) 
            route_section="$OPTARG" 
            if validate_g16_route "$route_section" ; then
              debug "Route specified with -R is fine."
            else
              warning "Syntax error in specified route section:"
              warning "  $route_section"
              fatal "Emergency stop."
            fi
            ;;

          #hlp   -l <ARG>   Load a specific route section stored as <ARG>.
          #hlp              If <ARG> is 'list', print all predefined values instead.
          #hlp
          l)
            if [[ $OPTARG =~ [Ll][Ii][Ss][Tt] ]] ; then
              local array_index=0
              for array_index in "${!g16_route_section_predefined[@]}" ; do
                (( array_index > 0 )) && printf '\n'
                printf '%5d : ' "$array_index" 
                local printvar printline=0
                while read -r printvar || [[ -n "$printvar" ]] ; do
                  if (( printline == 0 )) ; then
                    printf '%-80s\n' "$printvar"
                  else
                    printf '        %-80s\n' "$printvar"
                  fi
                  (( printline++ ))
                done <<< "$( fold -w80 -c -s <<< "${g16_route_section_predefined[$array_index]}" )"
              done
              exit 0
            elif is_integer "$OPTARG" ; then
              [[ -z ${g16_route_section_predefined[$OPTARG]} ]] && fatal "Out of range: $OPTARG"
              route_section="${g16_route_section_predefined[$OPTARG]}"
              message "Applied route section:"
              message "$(fold -w80 -c -s <<< "$route_section")"
            else
              fatal "No valid argument '$OPTARG'."
            fi
            ;;

          #hlp   -t <ARG>   Adds <ARG> to the end (tail) of the new input file.
          #hlp              If specified multiple times, each argument goes to a new line.
          #hlp 
          t) 
            use_custom_tail[${#use_custom_tail[@]}]="$OPTARG" 
            ;;

          #hlp   -C <ARG>   Specify the caption (title) of the job.
          #hlp              If specified multiple times, only the last one has an effect.
          #hlp              Replacement options:
          #hlp                '%F' input filename 
          #hlp                '%f' input without the xyz suffix
          #hlp                '%s' like '%f' filters out 'start'
          #hlp                '%j' job name
          #hlp                '%c' writes 'chrg {charge}'
          #hlp                '%M' writes 'mult {multiplicity}'
          #hlp                '%U' writes 'uhf {unpaired electrons}'
          #hlp              Default: 'Calculation: %j; %c; %M; %U; $(date +"%F %T (%Z)")'
          #hlp 
          C) 
            title_section="$OPTARG"
            ;;

          #hlp   -j <ARG>   Define the name of the job. 
          #hlp              If the argument is '%f' or '%s', use the input filename and 
          #hlp              filter the ending '.xyz' or '.start.xyz', respectively.
          #hlp              This will also be used as the basis for the filename.
          #hlp
          j)
            jobname="$OPTARG"
            ;;

          #hlp   -f <ARG>   Write inputfile to <ARG>.
          #hlp
          f)
            inputfile="$OPTARG"
            debug "Setting inputfile='$inputfile'."
            ;;

          #hlp   -c <ARG>   Define the charge of the molecule. (Default: 0)
          #hlp              If the pattern 'chrg <number>' is found in the file,
          #hlp              the script will use it. (Interface to xtb files)
          #hlp
          c) 
            validate_whole_number "$OPTARG" "charge"
            [[ -z $molecule_set_charge ]] || warning "Overwriting previously set charge ($molecule_set_charge)."
            molecule_set_charge="$OPTARG"
            ;;

          #hlp   -M <ARG>   Define the Multiplicity of the molecule. (Default: 1)
          #hlp              If specified with '-U <ARG>' only the last one will have an effect.
          #hlp              If the pattern 'mult <number>' is found in the file,
          #hlp              the script will use it. 
          #hlp
          M) 
            validate_integer "$OPTARG" "multiplicity"
            (( OPTARG == 0 )) && fatal "Multiplicity must not be zero."
            [[ -z $molecule_set_mult ]] || warning "Overwriting previously set multiplicity ($molecule_set_mult)."
            molecule_set_mult="$OPTARG"
            ;;

          #hlp   -U <ARG>   Define the number of unpaired electrons in the molecule. (Default: 0)
          #hlp              If specified with '-M <ARG>' only the last one will have an effect.
          #hlp              If the pattern 'uhf <number>' is found in the file,
          #hlp              the script will use it. (Interface to xtb files)
          #hlp
          U) 
            validate_integer "$OPTARG" "unpaired electrons"
            [[ -z $molecule_set_mult ]] || warning "Overwriting previously set multiplicity ($molecule_set_mult)."
            molecule_set_mult="$(( OPTARG + 1 ))"
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

exit_status=0
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

declare -a use_custom_route_keywords

# Evaluate Options

process_options "$@"
process_inputfile "$requested_inputfile" || exit_status="1"

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
exit $exit_status
