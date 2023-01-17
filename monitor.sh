#!/bin/sh
debug="${LSHC_DEBUGOUTPUT:-0}"
killlspid="${LSHC_KILLNOTDIE:-true}"
launchdelay="${LSHC_RESTARTDELAY:-5}"
retrylimit="${LSHC_RETRYLIMIT:-150}"
sleeptime="${LSHC_SLEEPTIME:-0.1s}"

function getlssendq () {
    #/bin/logspout pid
    lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
    if [ -n "${lspid}" ]; then
        lssendq=$(netstat -Wntp 2>/dev/null | grep "$lspid/logspout" | grep 'ESTABLISHED' | tr -s ' ' | cut -d' ' -f3)
        echo "${lssendq}"
    else
        echo "dead"
    fi
}

function checklogspout () {
    lssendq=$(getlssendq)
    n=0
    while [ "${lssendq}" != "0" ] && [ $n -lt $retrylimit ] && [ "${lssendq}" != "dead" ]; do
        sleep ${sleeptime}
        [ "${debug}" = "1" ] && echo -n +
        lssendq=$(getlssendq)
        n=$(( $n + 1 ))
    done

    if [ "${lssendq}" != "0" ]; then
        echo -n 'Timed out waiting for logspout to send data.  '
        if [ "${killlspid}" = "true" ]; then
            echo 'Terminating logspout'
            lspid=$(ps | grep /bin/logspout | grep -v grep | tr -s ' ' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | cut -d' ' -f1)
            if [ -n "${lspid}" ]; then
                kill ${lspid}
                sleep ${launchdelay}
            fi
            startlogspout
        else
            echo 'Exiting'
            exit
        fi
    fi
}

function startlogspout () {
    echo 'Starting logspout'
    /bin/logspout ${LSHC_LAUNCHARGS} &
}

startlogspout

echo 'Beginning monitor'
while true; do
    sleep 1
    [ "${debug}" = "1" ] && echo .
    checklogspout
done
