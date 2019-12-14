#!/bin/bash
# required: jq yq curl bc rev

RUN_DIR=`readlink -f "$(dirname "$0")"`
__log_mess () { echo -e `date +%F\ %T` - "$@"; }
__parsing_json_data () { echo "$1" | jq $2 | sed 's/"//g;  s/,$//' | grep -vx null; }

#Parsing config:
	__mess_of_invalid_config()
	{
		__log_mess "$1."
		__EXITING_1=1
	}

	__get_config_content()
	{
		[ -z "$CONFIG_FILE" ] && CONFIG_FILE='artifactory-cleaner.yml'

		if ! __CONFIG_CONTENT=`cat "$RUN_DIR/$CONFIG_FILE" 2> /dev/null`
		then
			__log_mess "No config found: $RUN_DIR/artifactory-cleaner.yml\nStopping..."
			exit 1
		fi
	}

	__get_config_content
	__parsing_config () { echo "$__CONFIG_CONTENT" | yq $1 | sed 's/"//g' | grep -vx null; }

	JF_TIMEOUT_RESCAN=`__parsing_config .timeout_rescan 2> /dev/null`
	[ -z "`echo "$JF_TIMEOUT_RESCAN" | grep -Ex '[0-9]{1,256}'`" -a -n "$JF_TIMEOUT_RESCAN" ] && __mess_of_invalid_config 'Rescan timeout is invalid.'

	JF_ADDRESS=`__parsing_config .jfrog_artifactory_address`
	[ -z "$JF_ADDRESS" ] && __mess_of_invalid_config 'Artifactory address not specified'
	[ "${JF_ADDRESS: -1}" == '/' ] && JF_ADDRESS=${JF_ADDRESS::-1}
	JF_PORT=`echo $JF_ADDRESS | rev | sed 's/:/: /' | rev | awk '{print $2}' | grep -Ex ':[0-9]{1,5}'`
	JF_ADDRESS=`echo $JF_ADDRESS | sed -E 's/:[0-9]{1,5}$//'`

	__get_config_parametrs()
	{
		REPOSITORY_OPTIONS="$(for INT in ${REPOSITORY_OPTIONS_ARREY[@]}; do echo "$INT"; done | sed 's#\\#\\\\#g')"
		unset INCR REPOSITORY_OPTIONS_ARREY[@]

		(( INC++ ))
		REPOSITORY_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .repo`
		SEARCH_NAME_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .name`
		SEARCH_RECURSIVE_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .recursive`
		SEARCH_RECURSIVE_COEFFICIENT_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .recursive.coefficient 2> /dev/null`
		SEARCH_NAME_IGNORE_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .name_ignore`
		SEARCH_RM_NON_EMPTY_DIRS_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .rm_non_empty_dirs`
		SEARCH_AGE_MORE_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .age | sed -n 's/ *//gp' | grep -Ex '>[0-9]{1,256}' | sed 's/^>//' | tail -n 1`
		SEARCH_AGE_LESS_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .age | sed -n 's/ *//gp' | grep -Ex '<[0-9]{1,256}' | sed 's/^<//' | tail -n 1`
		SEARCH_AGE_EQUAL_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .age | sed -n 's/ *//gp' | grep -Ex '=[0-9]{1,256}' | sed 's/^=//' | tail -n 1`
		SEARCH_SIZE_MORE_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .size  | sed -n 's/ *//gp' \
		| grep -Ex '>[0-9]{1,256}(gb|Gb|GB|mb|Mb|MB|kb|Kb|KB|)' | sed -E 's/^>//; s/(kb|Kb|KB)/000/g; s/(mb|Mb|MB)/000000/g; s/(gb|Gb|GB)/000000000/g' | tail -n 1`
		SEARCH_SIZE_LESS_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .size  | sed -n 's/ *//gp' \
		| grep -Ex '<[0-9]{1,256}(gb|Gb|GB|mb|Mb|MB|kb|Kb|KB|)' | sed -E 's/^<//; s/(kb|Kb|KB)/000/g; s/(mb|Mb|MB)/000000/g; s/(gb|Gb|GB)/000000000/g' | tail -n 1`
		SEARCH_SIZE_EQUAL_ARREY[$INC]=`__parsing_json_data "$REPOSITORY_OPTIONS" .size  | sed -n 's/ *//gp' \
		| grep -Ex '=[0-9]{1,256}(gb|Gb|GB|mb|Mb|MB|kb|Kb|KB|)' | sed -E 's/^=//; s/(kb|Kb|KB)/000/g; s/(mb|Mb|MB)/000000/g; s/(gb|Gb|GB)/000000000/g' | tail -n 1`

		if [ -z "`echo ${REPOSITORY_ARREY[$INC]}`" ] || [ "`echo "${REPOSITORY_ARREY[$INC]}" | sed 's| ||'`" != "${REPOSITORY_ARREY[$INC]}" ]
		then
			__log_mess "Missing expected repository name. Incorrect part of the config:\n$REPOSITORY_OPTIONS"
			exit 1

		elif [ "`echo "${SEARCH_NAME_ARREY[$INC]}" | sed 's| ||'`" != "${SEARCH_NAME_ARREY[$INC]}" ] || [ "`echo "${SEARCH_NAME_IGNORE_ARREY[$INC]}" | sed 's| ||'`" != "${SEARCH_NAME_IGNORE_ARREY[$INC]}" ]
		then
			__log_mess "Missing expected search name. Incorrect part of the config:\n$REPOSITORY_OPTIONS"
			exit 1
		fi

		[ -z "${SEARCH_AGE_MORE_ARREY[$INC]}" ] && [ -z "${SEARCH_AGE_LESS_ARREY[$INC]}" ] && [ -z "${SEARCH_AGE_EQUAL_ARREY[$INC]}" ] && \
		[ -z "${SEARCH_SIZE_MORE_ARREY[$INC]}" ] && [ -z "${SEARCH_SIZE_LESS_ARREY[$INC]}" ] && [ -z "${SEARCH_SIZE_EQUAL_ARREY[$INC]}" ] && \
		[ -z "${SEARCH_NAME_ARREY[$INC]}" ] && __mess_of_invalid_config "For the \"$CHECK_REPO\" repository, at least one sample attribute must be specified" && exit 1

		for INT in SEARCH_NAME_ARREY SEARCH_NAME_IGNORE_ARREY
		do
			if (( "$(eval echo \"\${$INT[$INC]}\" | wc -l)" > "1" ))
			then
				while read SEARCH_NAME
				do
					COMPOUND_SEARCH_NAME=$COMPOUND_SEARCH_NAME$NAMES_DELIMITER$SEARCH_NAME
					NAMES_DELIMITER='(.*)'
				done <<< "$(eval echo \"\${$INT[$INC]}\" | tail -n +2 | head -n -1)"
				eval $INT[$INC]=$COMPOUND_SEARCH_NAME
				unset NAMES_DELIMITER COMPOUND_SEARCH_NAME
			fi
		done
	}

	while read STRING_REPOSITORY_OPTIONS
	do
		if [ -n "$STRING_REPOSITORY_OPTIONS" ]
		then
			(( INCR++ ))
			REPOSITORY_OPTIONS_ARREY[$INCR]=$STRING_REPOSITORY_OPTIONS
		else
			__get_config_parametrs
		fi
	done <<< "`echo "$__CONFIG_CONTENT" | yq .repositories[] | sed 's#^}#}\n#g'`"
	__get_config_parametrs
	unset INC
#---



# Variable check:
	__variable_does_not_exist()
	{
		__log_mess "The \"$1\" variable is not defined, but is required when starting the container!"
		__EXITING_2=1
	}

	for INT in JF_USER JF_USER_TOKEN
	do
		[ -z "$(eval echo \$$INT)" ] && __variable_does_not_exist $INT
	done

	if [ -n "$__EXITING" ]
	then
		[ "$__EXITING_1" == '1' ] && __log_mess Invalid config!
		[ "$__EXITING_2" == '1' ] && __log_mess Stopping...
		exit 1
	fi
#---



#Parsing artifact data:
	__log_mess 'Start scanning artifacts...'
	START_TIME=`date +%s`

	__get_artifact_parametrs()
	{
		(( INC++ ))
		ARTIFACT_size[$INC]=`__parsing_json_data "$ARTIFACT_DATA" .size`
		ARTIFACT_uri[$INC]=`__parsing_json_data "$ARTIFACT_DATA" .uri`
		ARTIFACT_lastModified[$INC]=`__parsing_json_data "$ARTIFACT_DATA" .lastModified | sed 's/T[0-9]/\n/' | head -n 1`
		LINK_TO_INDEX_OF_PARAMETERS_ARRAY[$INC]=$INCREM

		[ -z "$INDEX_1" ] && { [ "`date +%S | sed 's/[0-9]$//'`" == '0' ] && { INDEX_1=1; INDEX_2=; INDEX_3=1; }; }
		[ -z "$INDEX_2" ] && { [ "`date +%S | sed 's/[0-9]$//'`" == '5' ] && { INDEX_1=; INDEX_2=1; }; }
		if (( "$(( "`date +%s`" - "$START_TIME" ))" > "40" )) && [ -n "$INDEX_3" ]
		then
			__log_mess "[INFO] Artifacts already scanned: $INC..."
			INDEX_3=
		fi
	}

	__connection_error()
	{
		__log_mess 'Error retrieving data from an artifact! Retrying after 3 min...'
		sleep 3m
	}

	__definition_of_the_first_empty_index () { INCREMENT=$(( "`for INT in ${ARTIFACT_children_url[@]}; do echo $INT; done | wc -l`" + 1 )); }

	INCREM=1
	INCR=1
	while [ -n "${REPOSITORY_ARREY[$INCREM]}" ]
	do
		__definition_of_the_first_empty_index
		ARTIFACT_children_url[$INCREMENT]=${REPOSITORY_ARREY[$INCREM]}

		while [ -n "${ARTIFACT_children_url[$INCR]}" ]
		do
			export JF_REPOSITORY_PATH=${ARTIFACT_children_url[$INCR]}
			[ "${JF_REPOSITORY_PATH: -1}" == '/' ] && export JF_REPOSITORY_PATH=${JF_REPOSITORY_PATH::-1}
			[ "${JF_REPOSITORY_PATH:0:1}" == '/' ] && export JF_REPOSITORY_PATH=${JF_REPOSITORY_PATH: +1}

			if ! ARTIFACTS_LIST="`export JF_ADDRESS=$JF_ADDRESS$JF_PORT; python "$RUN_DIR/artifacts_list.py" 2> /dev/null`"
			then
				__connection_error
				continue
			fi

			while read ARTIFACT
			do
				if [ -n "$ARTIFACT" ]
				then
					until ARTIFACT_DATA="$(curl --connect-timeout 90 --max-time 90 -s -H "Authorization: Bearer $JF_USER_TOKEN" -X GET $JF_ADDRESS$JF_PORT/api/storage`echo $ARTIFACT 2> /dev/null | sed -E "s#$JF_ADDRESS(:[0-9]{1,7}|)##"`)"
					do
						__connection_error
						continue
					done

					[ -n "`echo $VERBOSE_MODE | grep -Ex '(true|True|TRUE|1)'`" ] && __log_mess "Scan element:\n$ARTIFACT_DATA\n\n"
				fi

				if [ -n "`__parsing_json_data "$ARTIFACT_DATA" .children`" ]
				then
					if [ -z "`__parsing_json_data "$ARTIFACT_DATA" .children | grep -vx '\[\]'`" ]
					then
						__get_artifact_parametrs
						ARTIFACT_size[$INC]='EMPTY DIR'
					else
						if [ -n "`echo ${SEARCH_RECURSIVE_ARREY[$INCREM]} | grep -Ex '(true|True|TRUE|1)'`" ]
						then
							TEST_ARTIFACT_children_url=`__parsing_json_data "$ARTIFACT_DATA" .uri | sed -E "s#^$JF_ADDRESS(:[0-9]{1,7}|)/api/storage/##g"`

							for INT in ${ARTIFACT_children_url[@]}
							do
								if [ "$INT" == "$TEST_ARTIFACT_children_url" ]
								then
									EXIST_ARTIFACT_children_url=1
									break
								fi
							done

							if [ -z "$EXIST_ARTIFACT_children_url" ] && { [ -z "`echo ${SEARCH_RECURSIVE_COEFFICIENT_ARREY[$INCREM]} | grep -Ex '[0-9]{1,256}'`" ] || \
							(( "${SEARCH_RECURSIVE_COEFFICIENT_ARREY[$INCREM]}" >= "`echo $TEST_ARTIFACT_children_url | sed "s#${REPOSITORY_ARREY[$INCREM]}/##; s#/#\n#g" | wc -l`" )); }
							then
								__definition_of_the_first_empty_index
								ARTIFACT_children_url[$INCREMENT]=$TEST_ARTIFACT_children_url
							fi
							unset EXIST_ARTIFACT_children_url
						fi

						if [ -n "`echo ${SEARCH_RM_NON_EMPTY_DIRS_ARREY[$INCREM]} | grep -Ex '(true|True|TRUE|1)'`" ]
						then
							__get_artifact_parametrs
							ARTIFACT_size[$INC]='NON-EMPTY DIR'
						fi
					fi
				else
					__get_artifact_parametrs
				fi
			done <<< "$ARTIFACTS_LIST"

			(( INCR++ ))
		done

		(( INCREM++ ))
	done
	unset INC INCR INCREM INCREMENT ARTIFACT_children_url[@]
#---



#Applying conditions for the deletion of artifacts:

	__value_size_reducing()
	{
		if (( "$1" > '1000000000000' ))
		then
			echo $(echo "scale=1;$1/1000000000000" | bc)Tb
		elif (( "$1" > '1000000000' ))
		then
			echo $(echo "scale=1;$1/1000000000" | bc)Gb
		elif (( "$1" > '1000000' ))
		then
			echo $(echo "scale=1;$1/1000000" | bc)Mb
		elif (( "$1" > '1000' ))
		then
			echo $(echo "scale=1;$1/1000" | bc)Kb
		else
			echo $1
		fi
	}

	for ARTIFACT_API_LINK in ${ARTIFACT_uri[@]}
	do
		(( INC++ ))
		INCR=${LINK_TO_INDEX_OF_PARAMETERS_ARRAY[$INC]}
		ARTIFACT_PATH_IN_REPOSITORY=`echo $ARTIFACT_API_LINK | sed -E "s#$JF_ADDRESS(:[0-9]{1,7}|)/api/storage/${REPOSITORY_ARREY[$INCR]}##"`

		if ! [[ "$INT" =~ 'DIR' ]]
		then
			[ -n "${SEARCH_SIZE_MORE_ARREY[$INCR]}" ] && { (( "${ARTIFACT_size[$INC]}" > "${SEARCH_SIZE_MORE_ARREY[$INCR]}" )) || continue; }
			[ -n "${SEARCH_SIZE_LESS_ARREY[$INCR]}" ] && { (( "${ARTIFACT_size[$INC]}" < "${SEARCH_SIZE_LESS_ARREY[$INCR]}" )) || continue; }
			[ -n "${SEARCH_SIZE_EQUAL_ARREY[$INCR]}" ] && { (( "${ARTIFACT_size[$INC]}" == "${SEARCH_SIZE_EQUAL_ARREY[$INCR]}" )) || continue; }
		fi

		SEARCH_AGE=$(( ($(date '+%s') - $(date '+%s' -d "${ARTIFACT_lastModified[$INC]}")) / 86400 ))
		[ -n "${SEARCH_AGE_MORE_ARREY[$INCR]}" ] && { (( "$SEARCH_AGE" > "${SEARCH_AGE_MORE_ARREY[$INCR]}" )) || continue; }
		[ -n "${SEARCH_AGE_LESS_ARREY[$INCR]}" ] && { (( "$SEARCH_AGE" < "${SEARCH_AGE_LESS_ARREY[$INCR]}" )) || continue; }
		[ -n "${SEARCH_AGE_EQUAL_ARREY[$INCR]}" ] && { (( "$SEARCH_AGE" == "${SEARCH_AGE_EQUAL_ARREY[$INCR]}" )) || continue; }
		[ -n "${SEARCH_NAME_ARREY[$INCR]}" ] && { [ -n "`echo "$ARTIFACT_PATH_IN_REPOSITORY" | grep -E "${SEARCH_NAME_ARREY[$INCR]}"`" ] || continue; }
		[ -n "${SEARCH_NAME_IGNORE_ARREY[$INCR]}" ] && { [ -n "`echo "$ARTIFACT_PATH_IN_REPOSITORY" | grep -E "${SEARCH_NAME_IGNORE_ARREY[$INCR]}"`" ] && continue; }

		(( INCREM++ ))
		ARTIFACT_size_IS_DELETED[$INCREM]=${ARTIFACT_size[$INC]}
		export ARTIFACT_TO_REMOVE=`echo $ARTIFACT_API_LINK | sed 's|/api/storage||'`
		[ -n "`echo $EMULATION_MODE | grep -Ex '(false|False|FALSE|0)'`" ] && python "$RUN_DIR/rm_artifact.py"
		__log_mess "Deleting the artifact: $ARTIFACT_TO_REMOVE (Size: $(__value_size_reducing ${ARTIFACT_size[$INC]}), Created: $(date '+%d %B %Y' -d ${ARTIFACT_lastModified[$INC]}) — $SEARCH_AGE days ago)"
	done

	for INT in ${ARTIFACT_size_IS_DELETED[@]}
	do
		[[ "$INT" =~ 'DIR' ]] && INT=0
		TOTAL_SIZE_CLEARED=$(( "$TOTAL_SIZE_CLEARED" + "$INT" ))
	done

	if [ -z "$TOTAL_SIZE_CLEARED" ]
	then
		__log_mess 'Scanning complete. No found artifacts to delete.'
	else
		(( "$INCREM" > "1" )) && ARTIFACTS=artifacts || ARTIFACTS=artifact
		[ -n "`echo $EMULATION_MODE | grep -Ex '(false|False|FALSE|0)'`" ] || EMULATION_MODE_MESS='(emulation mode - without realy deleting files)'
		__log_mess "Clearing complete. Total cleared: $(__value_size_reducing $TOTAL_SIZE_CLEARED), $INCREM $ARTIFACTS is deleted $EMULATION_MODE_MESS"
	fi

	unset INC INCR INCREM TOTAL_SIZE_CLEARED ARTIFACT_size_IS_DELETED[@] ARTIFACT_uri[@] ARTIFACT_size[@] ARTIFACT_lastModified[@] REPOSITORY_ARREY[@] EMULATION_MODE_MESS
#---
