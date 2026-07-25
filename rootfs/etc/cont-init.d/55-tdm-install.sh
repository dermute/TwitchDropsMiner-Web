#!/bin/sh
#
# Make sure the current Twitch Drops Miner build is installed under /config
# before the application is started.
#

set -u

DATA_DIR="${TDM_DATA_DIR:-/config/app}"
RUN_DIR=/var/run/tdm

MAX_ATTEMPTS=5
RETRY_DELAY=15

mkdir -p "${DATA_DIR}" || exit 1
mkdir -p "${RUN_DIR}" || exit 1

# A stale pid file from a container that was killed would confuse the updater.
rm -f "${RUN_DIR}/app.pid"

if [ ! -f "${DATA_DIR}/.tdm-exec" ]; then
    # Nothing installed yet: the miner has to be downloaded before it can run.
    echo "No miner installed in ${DATA_DIR} yet, downloading it..."

    attempt=1
    while true; do
        /opt/tdm/bin/tdm-fetch.sh --dest "${DATA_DIR}"
        rc="$?"

        if [ "${rc}" -eq 0 ] || [ "${rc}" -eq 10 ]; then
            break
        fi

        if [ "${attempt}" -ge "${MAX_ATTEMPTS}" ]; then
            echo "ERROR: could not download Twitch Drops Miner after ${attempt}"
            echo "       attempts.  Check that the container can reach GitHub."
            exit 1
        fi

        echo "Retrying in ${RETRY_DELAY} seconds..."
        sleep "${RETRY_DELAY}"
        attempt=$((attempt + 1))
    done
elif is-bool-val-true "${TDM_AUTO_UPDATE:-1}"; then
    /opt/tdm/bin/tdm-fetch.sh --dest "${DATA_DIR}"
    case "$?" in
        0|10)
            ;;
        *)
            # Being unable to reach GitHub must not keep the miner from running
            # with the build that is already installed.
            echo "WARNING: could not check for a newer build, continuing with the"
            echo "         build currently installed in ${DATA_DIR}."
            ;;
    esac
fi

take-ownership "${DATA_DIR}"
take-ownership "${RUN_DIR}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
