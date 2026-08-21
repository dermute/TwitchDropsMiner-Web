#!/bin/sh
#
# Start Twitch Drops Miner.
#

set -u

DATA_DIR="${TDM_DATA_DIR:-/config/app}"
RUN_DIR=/var/run/tdm
PID_FILE="${RUN_DIR}/app.pid"
RESTART_DELAY="${TDM_RESTART_DELAY:-300}"

if [ ! -f "${DATA_DIR}/.tdm-exec" ]; then
    echo "No Twitch Drops Miner build is installed in ${DATA_DIR}."
    echo "Check the container log for errors reported during initialization."
    exit 1
fi

EXEC_NAME="$(cat "${DATA_DIR}/.tdm-exec")"

if [ ! -f "${DATA_DIR}/${EXEC_NAME}" ]; then
    echo "The miner executable '${EXEC_NAME}' is missing from ${DATA_DIR}."
    exit 1
fi

cd "${DATA_DIR}" || exit 1
[ -x "./${EXEC_NAME}" ] || chmod +x "./${EXEC_NAME}"

# The miner keeps all its persistent files (settings.json, cookies.jar, cache/,
# log.txt) next to its own executable, which is why it is installed under
# /config rather than somewhere in the image.
echo "Starting '${EXEC_NAME}' from ${DATA_DIR}..."

# shellcheck disable=SC2086 # TDM_ARGS holds several arguments.
"./${EXEC_NAME}" ${TDM_ARGS:-} &
APP_PID="$!"

mkdir -p "${RUN_DIR}" 2> /dev/null
echo "${APP_PID}" > "${PID_FILE}" 2> /dev/null

trap 'kill -TERM "${APP_PID}" 2> /dev/null' TERM INT

# `wait` returns as soon as a signal is caught, which is not necessarily the
# moment the miner terminates.
rc=0
while kill -0 "${APP_PID}" 2> /dev/null; do
    wait "${APP_PID}"
    rc="$?"
done

rm -f "${PID_FILE}" 2> /dev/null

# Exit codes are documented in the manual.txt shipped with the miner.
case "${rc}" in
    0)
        echo "Twitch Drops Miner exited normally."
        ;;
    1)
        echo "Twitch Drops Miner exited because of a CAPTCHA request or a fatal"
        echo "exception.  Open the web interface and complete the login, or check"
        echo "${DATA_DIR}/log.txt for details."
        ;;
    2)
        echo "Twitch Drops Miner rejected its command line arguments."
        echo "Check the value of TDM_ARGS: '${TDM_ARGS:-}'."
        ;;
    3)
        echo "Another instance of Twitch Drops Miner is already running and holds"
        echo "the lock on ${DATA_DIR}.  Make sure only one container uses this"
        echo "configuration directory."
        ;;
    4)
        echo "Twitch Drops Miner could not load ${DATA_DIR}/settings.json."
        echo "Fix or remove the file to continue."
        ;;
    130|143)
        # Terminated on purpose, by the updater or during container shutdown.
        echo "Twitch Drops Miner was terminated."
        ;;
    *)
        echo "Twitch Drops Miner exited with code ${rc}."
        ;;
esac

# With KEEP_APP_RUNNING enabled the supervisor restarts this script as soon as it
# exits.  Pace the restarts so that a permanent failure does not turn into a busy
# loop hammering Twitch.  A termination that was asked for is restarted right
# away.
if [ "${rc}" -ne 0 ] \
    && [ "${rc}" -ne 130 ] && [ "${rc}" -ne 143 ] \
    && [ "${RESTART_DELAY}" -gt 0 ]; then
    echo "Waiting ${RESTART_DELAY} seconds before exiting, to slow down restarts."
    trap 'kill "${SLEEP_PID}" 2> /dev/null; exit "${rc}"' TERM INT
    sleep "${RESTART_DELAY}" &
    SLEEP_PID="$!"
    wait "${SLEEP_PID}"
fi

exit "${rc}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
