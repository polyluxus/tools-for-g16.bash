#!/bin/bash

###
#
# tools-for-g16.bash -- 
#   A collection of tools for the help with Gaussian 16.
# Copyright (C) 2019-2020 Martin C Schwarzer
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
###

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This script will sumbit a Gaussian input file to the queueing system.
#hlp   It is designed to work on the RWTH compute cluster (CLAIX18)
#hlp   in combination with the slurm queueing system.
#hlp
#hlp   tools-for-g16.bash  Copyright (C) 2019  Martin C Schwarzer
#hlp   This program comes with ABSOLUTELY NO WARRANTY; this is free software, 
#hlp   and you are welcome to redistribute it under certain conditions; 
#hlp   please see the license file distributed alongside this repository,
#hlp   which is available when you type 'g16.tools-info.sh -L',
#hlp   or at <https://github.com/polyluxus/tools-for-g16.bash>.
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
    #shellcheck source=./resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0
    # Ensure that in/outputfile variables are empty
    unset inputfile
    unset outputfile
    
    # Import other functions
    #shellcheck source=./resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/process_gaussian.sh
    source "$resourcespath/process_gaussian.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=./resources/validate_numbers.sh
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
    validate_write_in_out_jobname "$testfile"
    debug "Jobname: $jobname; Input: $inputfile; Output: $outputfile."

    read_g16_input_file "$inputfile"
    if [[ -z "$route_section" ]] ; then
      warning "It appears that '$testfile' does not contain a valid (or recognised) route section."
      warning "Make sure this template file contains '#/#P/#N/#T' followed by a space."
      return 1
    else
      debug "Route (unmodified): $route_section"
    fi
    inputfile_modified="$jobname.gjf"
    backup_if_exists "$inputfile_modified"
    debug "Writing new input: $inputfile_modified"

    write_g16_input_file > "$inputfile_modified"
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
    message "Request a walltime of $requested_walltime."
    message "Request $requested_numCPU cores to run this job on."

    # Add a shebang and a comment
    echo "#!/bin/bash" >&9
    echo "# Submission script automatically created with $scriptname" >&9

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
      if [[ -n $dependency ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' 
        # which should be recognised by PBS
        echo "#PBS -W depend=afterok$dependency" >&9
      fi
      echo "jobid=\"\${PBS_JOBID%%.*}\"" >&9

    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      cat >&9 <<-EOF
			#BSUB -n $requested_numCPU
			#BSUB -M $overhead_memory
			#BSUB -W ${requested_walltime%:*}
			#BSUB -J ${jobname}
			#BSUB -o $submitscript.o%J
			#BSUB -e $submitscript.e%J
			EOF
      if [[ -n $dependency ]] ; then
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
      # Possibly an RWTH cluster specific setting
      if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
			  echo "#BSUB -a openmp" >&9
        if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
          echo "#BSUB -R select[hpcwork]" >&9
        fi
        if [[ "$qsys_project" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
          warning "No project selected."
        else
          echo "#BSUB -P $qsys_project" >&9
        fi
        if [[ "$bsub_machinetype" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
          warning "No machine type selected."
        else
          echo "#BSUB -m $bsub_machinetype" >&9
        fi
      fi

      local qsys_email_pattern='^(|1|[Yy][Ee][Ss]|[Aa][Cc][Tt][Ii][Vv][Ee]|[Dd][Ee][Ff][Aa][Uu][Ll][Tt])$'
      debug "qsys_email='$qsys_email'; pattern: $qsys_email_pattern"
      if [[ "$qsys_email" =~ $qsys_email_pattern ]] ; then
        debug "Standard slurm mail active."
        echo "#BSUB -N" >&9
      else
        debug "Standard slurm mail inactive ($qsys_email)."
      fi

      if [[ "$user_email" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        message "No email address given, notifications will be sent to system default."
      else
        echo "#BSUB -u $user_email" >&9
      fi
      echo "jobid=\"\${LSB_JOBID}\"" >&9

    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      cat >&9 <<-EOF
			#SBATCH --job-name='${jobname}'
			#SBATCH --output='$submitscript.o%j'
			#SBATCH --error='$submitscript.e%j'
			#SBATCH --nodes=1 
			#SBATCH --ntasks=1
			#SBATCH --cpus-per-task=$requested_numCPU
			#SBATCH --mem-per-cpu=$(( overhead_memory / requested_numCPU ))
			#SBATCH --time=${requested_walltime}
			EOF
      if [[ "$qsys_project" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        warning "No project selected."
      else
        echo "#SBATCH --account='$qsys_project'" >&9
      fi
      if [[ -n "$dependency" ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' 
        # which should be recognised by SLURM (like PBS)
        echo "#SBATCH --depend=afterok$dependency" >&9
      fi
      if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
        if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
          echo "#SBATCH --constraint=hpcwork" >&9
        fi
        echo "#SBATCH --export=NONE" >&9
      fi
      local qsys_email_pattern='^(|1|[Yy][Ee][Ss]|[Aa][Cc][Tt][Ii][Vv][Ee]|[Dd][Ee][Ff][Aa][Uu][Ll][Tt])$'
      debug "qsys_email='$qsys_email'; pattern: $qsys_email_pattern"
      if [[ "$qsys_email" =~ $qsys_email_pattern ]] ; then
        debug "Standard slurm mail active."
        echo "#SBATCH --mail-type=END,FAIL" >&9
      else
        debug "Standard slurm mail inactive ($qsys_email)."
      fi
      if [[ "$user_email" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        debug "No email address given, notifications will be sent to system default."
      else
        echo "#SBATCH --mail-user=$user_email" >&9
      fi
      echo "jobid=\"\${SLURM_JOB_ID}\"" >&9
    else
      fatal "Unrecognised queueing system '$queue'."
    fi

    echo "" >&9
  
    # Extra mail interface
    local xmail_pattern='^(1|[Yy][Ee][Ss]|[Aa][Cc][Tt][Ii][Vv][Ee])$'
    debug "xmail_interface='$xmail_interface'; xmail_cmd='$xmail_cmd'; pattern: $xmail_pattern"
    if [[ "$xmail_interface" =~ $xmail_pattern ]] ; then
      warning "The extra mail interface is still experimental."
      debug "Pattern was found (${BASH_REMATCH[0]})."
      cat >&9 <<-EOF
				# Add the User's bin directory to PATH to be sure not to miss local commands
				PATH="\$HOME/bin:\$PATH"
				
				sendmail () {
				  local mail_subject='\\(^o^)/ COMPLETED, '
				  (( joberror > 0 ))  && mail_subject='( ; __ ; ) FAILED, '
				  mail_subject+="${queue_short^} Job_id=\$jobid Name=$jobname ended"
				  echo "Sending mail with: $xmail_cmd -s \"\$mail_subject\""
				  ${xmail_cmd:-mail} -s "\$mail_subject"
				  sleep 10
				}
				
				EOF
    else
      debug "Pattern was not found, extra mail interface inactive."
    fi

    # Initialise variables, insert cleanup procedure, trap cleanup
    local tempdir_pattern='^(|[Tt][Ee]?[Mm][Pp]([Dd][Ii][Rr])?|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$'
    debug "g16_scratch='$g16_scratch'; pattern: $tempdir_pattern"
    if [[ "$g16_scratch" =~ $tempdir_pattern ]] ; then
      debug "Pattern was found."
      #shellcheck disable=SC2016
      g16_scratch='$( mktemp --directory --tmpdir )'
    else
      debug "Pattern was not found."
    fi

    cat >&9 <<-EOF
			# Make a new scratch directory
			g16_basescratch="$g16_scratch"
			g16_subscratch="\$g16_basescratch/g16job\$jobid"
			mkdir -p "\$g16_subscratch" || { echo "Failed to create scratch directory" >&2 ; exit 1 ; }
			
			cleanup () {
			  echo "Looking for files with filesize zero and delete them in '\$g16_subscratch'."
			  find "\$g16_subscratch" -type f -size 0 -exec rm -v {} \\;
			  echo "Deleting scratch '\$g16_subscratch' if empty."
			  find "\$g16_subscratch" -maxdepth 0 -empty -exec rmdir -v {} \\;
			  [[ -e "\$g16_subscratch" ]] && mv -v -- "\$g16_subscratch" "$PWD/${jobname}.scr\$jobid"
			  echo "Deleting scratch '\$g16_basescratch' if empty."
			  find "\$g16_basescratch" -maxdepth 0 -empty -exec rmdir -v {} \\;
			}
			
			EOF

    if [[ "$xmail_interface" =~ $xmail_pattern ]] ; then
      cat >&9 <<-EOF
				cleanup_and_sendmail () {
				  sendmail
				  cleanup
				}
				
				trap cleanup_and_sendmail EXIT SIGTERM
				EOF
    else
      echo "trap cleanup EXIT SIGTERM" >&9
    fi

    echo "" >&9

    # How Gaussian is loaded
    if [[ "$load_modules" =~ [Tt][Rr][Uu][Ee] ]] ; then
      (( ${#g16_modules[*]} == 0 )) && fatal "No modules to load."
      # Only necessary in interactive mode for rwth
      # source /usr/local_host/etc/init_modules.sh
      cat >&9 <<-EOF
			# Export current (at the time of execution) MODULEPATH (to be safe, could be set in bashrc)
			export MODULEPATH="$MODULEPATH"
			module load ${g16_modules[*]} 2>&1
			# Because otherwise it would go to the error output.
			
			EOF
    else
      [[ -z "$g16_installpath" ]] && fatal "Gaussian path is unset."
      [[ -e "$g16_installpath/g16/bsd/g16.profile" ]] || fatal "Gaussian profile does not exist."
      cat >&9 <<-EOF
			g16root="$g16_installpath"
			export g16root
			. \$g16root/g16/bsd/g16.profile
			EOF

      if [[ "$nbo6_interface" =~ [Aa][Cc][Tt][Ii][Vv][Ee] ]] ; then
        [[ -z "$nbo6_installpath" ]] && fatal "NBO6 path is unset."
        [[ -e "$nbo6_installpath/bin" ]] || fatal "NBO6 bin directory does not exist."
        cat >&9 <<-EOF
				PATH="$nbo6_installpath/bin:$PATH"
				export PATH
				EOF
      else
        debug "External NBO6 interface is inactive."
      fi
    fi

    # Most of the body is the same for all queues 
    cat >&9 <<-EOF
		# Get some information o the platform
		echo "This is \$(uname -n)"
		echo "OS \$(uname -o) (\$(uname -p))"
		echo "Running on $requested_numCPU \
		      \$(grep 'model name' /proc/cpuinfo|uniq|cut -d ':' -f 2)."
		echo "Calculation $inputfile_modified from $PWD."
		echo "Working directry is $PWD"
		
		cd "$PWD" || exit 1
		
		# Pass scratch on to Gaussian (overwrites defaults from module)
		export GAUSS_SCRDIR="\$g16_subscratch"
		
		EOF

    # Insert additional environment variables
    if [[ -n "$manual_env_var" ]]; then
      echo "export $manual_env_var" >&9
      debug "export $manual_env_var"
    fi

    #shellcheck disable=SC2016
    echo 'echo "Start: $(date)"' >&9
    if [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      # Executing something is different for SLURM
      echo "srun g16 < '$inputfile_modified' > '$outputfile'" >&9
    else
      echo "g16 < '$inputfile_modified' > '$outputfile'" >&9 
    fi
    cat >&9 <<-EOF
		joberror=\$?
		echo "End  : \$(date)"
		exit \$joberror
		EOF

    # Close file descriptor
    echo "# $scriptname is part of $softwarename $version ($versiondate)" >&9
    exec 9>&-
    message "Written submission script '$submitscript'."
    return 0
}

submit_jobscript_hold ()
{
    local queue="$1" submit_id submit_message queue_cmd
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      if queue_cmd=$( command -v qsub ) ; then
        submit_id="$( $queue_cmd -h "$submitscript")" || exit_status="$?"
        submit_message="
          Submitted as $submit_id.
          Use 'qrls $submit_id' to release the job."
      else
        exit_status=1
        submit_message="Command 'qsub' not found."
      fi
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      if queue_cmd=$( command -v bsub ) ; then
        submit_message="$( $queue_cmd -H < "$submitscript" 2>&1 )" || exit_status="$?"
      else
        exit_status=1
        submit_message="Command 'bsub' not found."
      fi
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      if queue_cmd=$( command -v sbatch ) ; then
        submit_message="$( $queue_cmd --hold "$submitscript" 2>&1 )" || exit_status="$?"
      else
        exit_status=1
        submit_message="Command 'sbatch' not found."
      fi
    fi
    if (( exit_status > 0 )) ; then
      warning "Submission went wrong."
      warning "$submit_message"
    else
      message "$submit_message"
    fi
    return $exit_status
}

submit_jobscript_keep ()
{
    local queue="$1" 
    message "Created submit script, use"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      message "  qsub $submitscript"
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      message "  bsub < $submitscript"
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      message "  sbatch $submitscript" 
    fi
    message "to start the job."
}

submit_jobscript_run  ()
{
    local queue="$1" submit_message queue_cmd
    debug "queue=$queue; submitscript=$submitscript"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      if queue_cmd=$( command -v qsub ) ; then
        submit_message="Submitted as $( qsub "$submitscript" )" || exit_status="$?"
      else
        exit_status=1
        submit_message="Command 'qsub' not found."
      fi
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb]-[Rr][Ww][Tt][Hh] ]] ; then
      if queue_cmd=$( command -v bsub ) ; then
        submit_message="$( $queue_cmd < "$submitscript" 2>&1 )" || exit_status="$?"
      else
        exit_status=1
        submit_message="Command 'bsub' not found."
      fi
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      if queue_cmd=$( command -v sbatch ) ; then
      submit_message="$( $queue_cmd "$submitscript" 2>&1 )" || exit_status="$?"
      else
        exit_status=1
        submit_message="Command 'sbatch' not found."
      fi
    else
      fatal "Unrecognised queueing system '$queue'."
    fi
    if (( exit_status > 0 )) ; then
      warning "Submission went wrong."
      warning "$submit_message"
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
    debug "Processing options: $*"
    #hlp   Options:
    #hlp    
    local OPTIND=1 

    while getopts :m:p:d:w:b:e:j:Hkq:Q:P:M:u:sh options ; do
        debug "Current option: $options"
        case $options in

          #hlp     -m <ARG> Define the total memory to be used in megabyte.
          #hlp              The total request will be larger to account for 
          #hlp              overhead which Gaussian may need. (Default: $requested_memory)
          #hlp
            m) 
               validate_integer "$OPTARG" "the memory"
               if (( OPTARG == 0 )) ; then
                 fatal "Memory limit must not be zero."
               fi
               requested_memory="$OPTARG" 
               ;;

          #hlp     -p <ARG> Define number of professors to be used. (Default: $requested_numCPU)
          #hlp
            p) 
               validate_integer "$OPTARG" "the number of threads"
               if (( OPTARG == 0 )) ; then
                 fatal "Number of threads must not be zero."
               fi
               requested_numCPU="$OPTARG" 
               ;;

          #hlp     -d <ARG> Define disksize via the MaxDisk keyword (MB; default: $requested_maxdisk).
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

          #hlp     -w <ARG> Define maximum walltime. (Default: $requested_walltime)
          #hlp              The colon separated format [[HH:]MM:]SS is supported, 
          #hlp              as well as suffixing an integer value with d/h/m (days/hours/minutes).
          #hlp              These two input formats cannot be combined; 
          #hlp              a purely numeric value will be taken as seconds (the suffix 's' is illegal).
          #hlp
            w) 
               if requested_walltime="$(format_duration "$OPTARG")" ; then 
                 debug "Reformatted walltime duration to '$requested_walltime'."
               else
                 fatal "Encountered error setting the walltime. Abort."
               fi
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
          #hlp
            H) 
               requested_submit_status="hold"
               if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
                 warning "(RWTH) Current permissions prevent releasing the job."
               fi 
               ;;

          #hlp     -k       Only create (keep) the jobscript, do not submit it.
          #hlp
            k) 
               requested_submit_status="keep"
               ;;

          #hlp     -q       submit to queue --TODO--
          #hlp              
            q) warning "The submission to a specific queue is not yet possible." ;;

          #hlp     -Q <ARG> Which type of job script should be produced. (Default: $request_qsys).
          #hlp              Arguments currently implemented: pbs-gen, bsub-gen, slurm-gen, 
          #hlp              Special cases: bsub-rwth, slurm-rwth
          #hlp
            Q) request_qsys="$OPTARG" ;;

          #hlp     -P <ARG> Account to project (BSUB), or account (SLURM). (Default: $qsys_project)
          #hlp              It has currently no effect if PBS is set as the queue.
          #hlp              If the argument is 'default', '0', or '', it reverts to system settings.
          #hlp
            P) 
               qsys_project="$OPTARG"
               ;;

          #hlp     -M <ARG> Request a certain machine type, also selects '-Q bsub-rwth'.
          #hlp              Writes '#BSUB -m <ARG>' to the submit file.
          #hlp              No sanity check will performed.
          #hlp              If the argument is 'default', '0', or '', it reverts to system settings.
          #hlp
            M) 
               bsub_machinetype="$OPTARG"
               request_qsys="bsub-rwth"  
               ;;

          #hlp     -u <ARG> Set user email address (BSUB/SLURM; default: $user_email)
          #hlp              In other queueing systems it just won't be used.
          #hlp              If the argument is 'default', '0', or '', it reverts to system settings.
          #hlp
            u) 
               if [[ "$OPTARG" =~ ^(|0|[Dd][Ee][Ff][Aa][Uu][Ll][Tt])$ ]] ; then
                 user_email="default"
                 continue
               elif validate_email "$OPTARG" "the user email address" ; then
                 user_email="$OPTARG"
               fi
               ;;

          #hlp     -s       Suppress logging messages of the script.
          #hlp              (May be specified multiple times.)
          #hlp
            s) (( stay_quiet++ )) ;;

          #hlp     -h       this help.
          #hlp
            h) helpme ;;

          #hlp     --       Close reading options.
          # This is the standard closing argument for getopts, it needs no implemenation.

           \?) fatal "Invalid option: -$OPTARG." ;;

            :) fatal "Option -$OPTARG requires an argument." ;;

        esac
    done

    # Shift all variables processed to far
    shift $((OPTIND-1))

    if [[ -z "$1" ]] ; then 
      fatal "There is no inputfile specified"
    fi

    # The test whether the file exists or not will be done 
    # when extracting more information
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
if ( return 0 2>/dev/null ) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  debug "Script is sourced. Return now."
  return 0
fi

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

if [[ -n $g16_tools_rc_loc ]] ; then
  #shellcheck source=./g16.tools.rc 
  . "$g16_tools_rc_loc"
  message "Configuration file '${g16_tools_rc_loc/*$HOME/<HOME>}' applied."
  if [[ "${configured_version}" =~ ^${version%.*} ]] ; then 
    debug "Config: $configured_version ($configured_versiondate); Current: $version ($versiondate)."
  else
    warning "Configured version was ${configured_version:-unset} (${configured_versiondate:-unset}),"
    warning "and probably needs an update to $version ($versiondate)."
  fi
else
  debug "No custom settings found."
fi

# Evaluate Options

process_options "$@" || fatal "Unrecoverable error processing script options. Abort."
process_inputfile "$requested_inputfile" || fatal "Unrecoverable error processing the input file. Abort."
write_jobscript "$request_qsys" || fatal "Unrecoverable error writing the job script. Abort."
submit_jobscript "$request_qsys" "$requested_submit_status" || fatal "Unrecoverable error during job submission. Abort."

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"
