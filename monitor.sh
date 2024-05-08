#!/bin/sh

debug="${LSHC_DEBUGOUTPUT:-0}"
killlspid="${LSHC_KILLNOTDIE:-true}"
noaction="${LSHC_NOACTION:-false}"
launchdelay="${LSHC_RESTARTDELAY:-5}"
retrylimit="${LSHC_RETRYLIMIT:-150}"
sleeptime="${LSHC_SLEEPTIME:-0.1s}"
waitlimit="${LSHC_WAITLIMIT:-3}"
waitmonitoring="${LSHC_WAITMONITORING:-true}"
waitsleep="${LSHC_WAITSLEEP:-90s}"

getlssendq () {
    #/bin/logspout pid
    # lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
    lspid=$(pgrep /bin/logspout)
    if [ -n "${lspid}" ]; then
        lssendq=$(netstat -Wntp 2>/dev/null | grep "${lspid}/logspout" | grep 'ESTABLISHED' | tr -s ' ' | cut -d' ' -f3)
        if [ -n "${lssendq}" ]; then
            if [ "${waitmonitoring}" = "true" ]; then
                lsport=$(netstat -Wntp 2>/dev/null | grep "${lspid}/logspout" | grep 'ESTABLISHED' | tr -s ' ' | cut -d' ' -f5 | cut -d':' -f2)
                if [ -n "${lsport}" ]; then
                    lswaits=$(netstat -Wntp 2>/dev/null | grep ":${lsport}" | grep -c '_WAIT')
                    [ "${debug}" = "2" ] && >&2 echo "lswaits=${lswaits}"
                    if [ -n "${lswaits}" ] && [ "${lswaits}" -ge "${waitlimit}" ]; then
                        [ "${debug}" = "1" ] && >&2 echo "Changing lssendq from ${lssendq} to 'dead' due to lswaits=${lswaits}"
                        lssendq="dead"
                        sleep "${waitsleep}"
                    fi
                fi
            fi
        fi
        echo "${lssendq}"
    else
        echo "dead"
    fi
}

checklogspout () {
    lssendq=$(getlssendq)
    old_lssendq=${lssendq}
    n=0
    while [ "${lssendq}" != "0" ] && [ $n -lt "${retrylimit}" ] && [ "${lssendq}" != "dead" ] && [ "${old_lssendq}" -le "${lssendq}" ]; do
        sleep "${sleeptime}"
        # [ "${debug}" = "1" ] && echo -n +
        [ "${debug}" = "1" ] && printf '+'
        old_lssendq=${lssendq}
        lssendq=$(getlssendq)
        n=$(( n + 1 ))
    done

    if [ "${lssendq}" = "0" ] || [ "${old_lssendq}" -gt "${lssendq}" ]; then
        return
    fi

    # echo -n 'Timed out waiting for logspout to send data.  '
    printf 'Timed out waiting for logspout to send data.  '
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
            sleep "${launchdelay}"
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
}

startlogspout

echo 'Beginning monitor'
while true; do
    sleep 1
    [ "${debug}" = "1" ] && echo .
    checklogspout
done
