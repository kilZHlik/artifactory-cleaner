#!/bin/bash
RUN_DIR=`readlink -f "$(dirname "$0")"`

while true
do
	source "$RUN_DIR/processor.sh"
	
	if [ -z "$JF_TIMEOUT_RESCAN" ]
	then
		__log_mess "The repository scan schedule is disabled. To manually start a scan, use the command: docker exec -it <image_name> artifactory-cleaner <arguments>"
		unset TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY
		
		while true
		do
			if [ -n "`echo "$JF_TIMEOUT_RESCAN" | grep -Ex '[0-9]{1,256}'`" ]
			then
				__log_mess "The repository scan schedule is enabled."
				break
			fi
			sleep 30
			__get_config_content
			JF_TIMEOUT_RESCAN=`__parsing_config .timeout_rescan`
		done
		continue
	fi

	#Timeout Rescan:
		if [ -n "$TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY" ]
		then
			if (( "60" < "$TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY" ))
			then
				while read __HOURS __MINUTES
				do
					MINUTES=$(( $__MINUTES / 10 * 6 ))
					HOURS=$__HOURS
				done <<< "`echo "scale=2;$TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY/60" | bc | sed 's/\./ /'`"

				if (( "24" < "$HOURS" ))
				then
					while read __DAYS __HOURS
					do
						HOURS=$(( $__HOURS / 100 * 24 ))
						DAYS=$__DAYS
						
					done <<< "`echo "scale=2;$HOURS/24" | bc | sed 's/\./ /'`"
				fi
				[ -z "$DAYS" ] && DAYS=0

				TIME_TO_DEFINE_A_START_JOB="${DAYS}d ${HOURS}h ${MINUTES}min"
			else
				TIME_TO_DEFINE_A_START_JOB="0d 0h ${TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY}min"
			fi

			__log_mess "Pause for compliance with the periodicity of the scan, before determining a new start: $TIME_TO_DEFINE_A_START_JOB"
			sleep ${TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY}m
		fi

		JF_TIMEOUT_RESCAN=$(( "$JF_TIMEOUT_RESCAN" * "1440" ))
		GENERATED_TIMEOUT=`shuf -i 1-$JF_TIMEOUT_RESCAN -n 1`
		TIMEOUT_OF_THE_REMAINING_WAIT_ACCORDING_TO_THE_SPECIFIED_FREQUENCY=$(( "$JF_TIMEOUT_RESCAN" - "$GENERATED_TIMEOUT" ))
		__log_mess "Next scan time for Artifactory repositories: $(date -d "+$GENERATED_TIMEOUT min" '+%d %B %Y in %Hh:%Mmin')"
		sleep ${GENERATED_TIMEOUT}m
	#---
done
