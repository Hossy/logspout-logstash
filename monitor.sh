#!/bin/sh

debug="${LSHC_DEBUGOUTPUT:-0}"
killlspid="${LSHC_KILLNOTDIE:-true}"
launchdelay="${LSHC_RESTARTDELAY:-5}"
retrylimit="${LSHC_RETRYLIMIT:-150}"
sleeptime="${LSHC_SLEEPTIME:-0.1s}"
waitlimit="${LSHC_WAITLIMIT:-3}"
waitmonitoring="${LSHC_WAITMONITORING:-true}"
waitsleep="${LSHC_WAITSLEEP:-90s}"

getlssendq () {
    #/bin/logspout pid
    lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
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
    n=0
    while [ "${lssendq}" != "0" ] && [ $n -lt "${retrylimit}" ] && [ "${lssendq}" != "dead" ]; do
        sleep "${sleeptime}"
        [ "${debug}" = "1" ] && echo -n +
        lssendq=$(getlssendq)
        n=$(( n + 1 ))
    done

    if [ "${lssendq}" != "0" ]; then
        echo -n 'Timed out waiting for logspout to send data.  '
        [ "${debug}" = "1" ] && echo -n "lssendq=${lssendq}.  "
        if [ "${killlspid}" = "true" ]; then
            echo 'Terminating logspout'
            lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
            if [ -n "${lspid}" ]; then
                kill "${lspid}"
                sleep "${launchdelay}"
            fi
            startlogspout
        else
            echo 'Exiting'
            exit
        fi
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
