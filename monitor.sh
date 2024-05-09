#!/bin/sh

checkinterval="${LSHC_CHECKINTERVAL:-1}"        # Sleep interval between normal checks
debug="${LSHC_DEBUGOUTPUT:-0}"                  # Set to 1 to enable
killlspid="${LSHC_KILLNOTDIE:-true}"            # Anything not 'true' disables restarts; Terminates entrypoint instead
launchdelay="${LSHC_LAUNCHDELAY:-0s}"           # Launch delay to start/resume monitoring
noaction="${LSHC_NOACTION:-false}"              # Set to true to enable
restartdelay="${LSHC_RESTARTDELAY:-5}"          # Restart delay
retrylimit="${LSHC_RETRYLIMIT:-150}"            # Number of times to recheck send-Q
sleeptime="${LSHC_SLEEPTIME:-0.1s}"             # Sleep time in between send-Q rechecks
waitlimit="${LSHC_WAITLIMIT:-3}"                # Limit of TIME_WAIT connections before triggering restart
waitmonitoring="${LSHC_WAITMONITORING:-true}"   # Anything not 'true' disables TIME_WAIT connection monitoring
waitsleep="${LSHC_WAITSLEEP:-90s}"              # Restart delay for TIME_WAIT connection monitoring (in addition to restartdelay)

getlssendq () {
    #/bin/logspout pid
    # lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
    lspid=$(pgrep /bin/logspout)
    if [ -n "${lspid}" ]; then
        n=0
        # Check netstat up to three times with checkinterval duration in between checks
        while [ "${n}" -lt 3 ]; do
            n=$(( n + 1 ))
            # lssendq=$(netstat -Wntp 2>/dev/null | grep "${lspid}/logspout" | grep 'ESTABLISHED' | tr -s ' ' | cut -d' ' -f3)
            netstat_result=$(netstat -Wntp 2>/dev/null)
            if [ -n "${netstat_result}" ]; then
                # awk '!seen[$4,$5]++' is needed because sometimes netstat duplicates lines.  This deduplicates the lines based on source and destination.
                # Example netstat output:
                #   tcp        0 2422871 127.0.0.1:57858                                     127.0.0.1:5041                                      ESTABLISHED 6/logspout
                #   tcp        0       0 10.42.142.135:9600                                  10.42.184.30:39544                                  TIME_WAIT   -
                #   tcp        0 2380887 127.0.0.1:57858                                     127.0.0.1:5041                                      ESTABLISHED 6/logspout
                lssendq=$(echo "${netstat_result}" | awk -v lspid="${lspid}" '$NF == lspid"/logspout" && $(NF-1) == "ESTABLISHED" && !seen[$4,$5]++ { print }' | tr -s ' ' | cut -d' ' -f3)
                if [ -n "${lssendq}" ]; then
                    break
                fi
            fi
            sleep "${checkinterval}"
        done
        if [ -n "${lssendq}" ]; then
            if [ "$(echo "${lssendq}" | wc -l)" -gt "1" ]; then
                echo 'Multiple logstash connections detected'
                printf 'lspid=%s\nnetstat data:\n%s\n' "${lspid}" "${netstat_result}"
            elif [ "${waitmonitoring}" = "true" ]; then
                # lsport=$(netstat -Wntp 2>/dev/null | grep "${lspid}/logspout" | grep 'ESTABLISHED' | tr -s ' ' | cut -d' ' -f5 | cut -d':' -f2)
                lsport=$(netstat -Wntp 2>/dev/null | awk -v lspid="${lspid}" '$NF == lspid"/logspout" && $(NF-1) == "ESTABLISHED" && !seen[$4,$5]++ { split($5, port, ":"); print port[2] }')
                if [ -n "${lsport}" ]; then
                    # lswaits=$(netstat -Wntp 2>/dev/null | grep ":${lsport}" | grep -c '_WAIT')
                    lswaits=$(netstat -Wntp 2>/dev/null | awk -v lsport="${lsport}" '$5 ~ ":"lsport"$" && $(NF-1) ~ "_WAIT$" && !seen[$4,$5]++ { count++ } END { print count }')
                    # [ "${debug}" = "2" ] && >&2 echo "lswaits=${lswaits}"
                    if [ -n "${lswaits}" ] && [ "${lswaits}" -ge "${waitlimit}" ]; then
                        # [ "${debug}" = "1" ] && >&2 echo "Changing lssendq from ${lssendq} to 'dead' due to lswaits=${lswaits}"
                        lssendq="time_wait"
                        sleep "${waitsleep}"
                    fi
                fi
            fi
            echo "${lssendq}"
        else
            echo "no established connections"
            printf 'lspid=%s\nnetstat data:\n%s\n' "${lspid}" "${netstat_result}"
        fi
    else
        echo "not running"
    fi
}

checklogspout () {
    lssendq=$(getlssendq)
    old_lssendq=${lssendq}
    n=0
    while [ -n "${lssendq}" ] && [ "${lssendq}" != "0" ] && [ "${n}" -lt "${retrylimit}" ] && expr "${lssendq}" : '^[0-9]\+$' >/dev/null 2>&1 && [ "${old_lssendq}" -le "${lssendq}" ]; do
        sleep "${sleeptime}"
        # [ "${debug}" = "1" ] && echo -n +
        [ "${debug}" = "1" ] && printf '+'
        old_lssendq=${lssendq}
        lssendq=$(getlssendq)
        n=$(( n + 1 ))
    done

    if [ "${lssendq}" = "0" ]; then
        return
    fi
    if [ -n "${old_lssendq}" ] && [ -n "${lssendq}" ] && expr "${old_lssendq}" : '^[0-9]\+$' >/dev/null 2>&1 && expr "${lssendq}" : '^[0-9]\+$' >/dev/null 2>&1 && [ "${old_lssendq}" -gt "${lssendq}" ]; then
        return
    fi

    if [ "${lssendq}" = "not running" ]; then
        printf 'Found logspout not running.  '
        if [ "${killlspid}" = "true" ]; then
            echo 'Restarting logspout.'
            startlogspout
        else
            echo 'Exiting'
            exit
        fi
    fi

    # echo -n 'Timed out waiting for logspout to send data.  '
    printf 'Timed out waiting for logspout to send data.  Reason: '
    if expr "${lssendq}" : '^[0-9]\+$' >/dev/null 2>&1; then
        printf 'Send-Q'
    else
        printf '%s' "${lssendq}"
    fi
    printf '.  '
    # [ "${debug}" = "1" ] && echo -n "lssendq=${lssendq}.  "
    [ "${debug}" = "1" ] && printf "lssendq=%s.  " "${lssendq}"
    if [ "${noaction}" = "true" ]; then
        echo 'Doing nothing per user request.'
    elif [ "${killlspid}" = "true" ]; then
        echo 'Terminating logspout'
        # lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
        lspid=$(pgrep /bin/logspout)
        if [ -n "${lspid}" ]; then
            kill "${lspid}"
            sleep "${restartdelay}"
        fi
        startlogspout
    else
        echo 'Exiting'
        exit
    fi
}

startlogspout () {
    echo 'Starting logspout'
    # shellcheck disable=SC2086  # Globbing on purpose
    /bin/logspout ${LSHC_LAUNCHARGS} &
    lspid=$!
    echo "logspout PID = ${lspid}"
    echo 'Waiting for logspout to establish connection'
    while : ; do
        if test -d /proc/${lspid}; then
            if netstat -Wntp 2>/dev/null | grep "${lspid}/logspout" | grep -q 'ESTABLISHED'; then
                echo 'Connection established'
                break
            fi
        else
            echo 'logspout died before establishing a connection'
            break
        fi
        [ "${debug}" = "1" ] && echo c
        sleep "${checkinterval}"
    done
    if test -d /proc/${lspid}; then
        [ "${debug}" = "1" ] && echo l
        sleep "${launchdelay}"
    else
        echo 'logspout failed to stay running. Exiting.'
        exit
    fi
    echo 'logspout started'
}

startlogspout

echo 'Beginning monitor'
while : ; do
    sleep "${checkinterval}"
    [ "${debug}" = "1" ] && echo .
    checklogspout
done
