#!/bin/sh
#
# Install and start Twitch Drops Miner from the persistent data directory.
#

set -u

APP_DIR=/opt/tdm/app
DATA_DIR="${TDM_DATA_DIR:-/config/app}"
RESTART_DELAY="${TDM_RESTART_DELAY:-300}"

case "${RESTART_DELAY}" in
    ''|*[!0-9]*)
        echo "TDM_RESTART_DELAY must be a non-negative integer, got '${RESTART_DELAY}'."
        exit 2
        ;;
esac

if [ ! -f "${APP_DIR}/.tdm-exec" ] || [ ! -f "${APP_DIR}/.tdm-build-id" ]; then
    echo "ERROR: this image does not contain a Twitch Drops Miner build."
    exit 1
fi

mkdir -p "${DATA_DIR}" || exit 1

IMAGE_BUILD_ID="$(cat "${APP_DIR}/.tdm-build-id")"
DATA_BUILD_ID="$(cat "${DATA_DIR}/.tdm-build-id" 2> /dev/null || true)"
IMAGE_EXEC_NAME="$(cat "${APP_DIR}/.tdm-exec")"
DATA_EXEC_NAME="$(cat "${DATA_DIR}/.tdm-exec" 2> /dev/null || true)"

if [ "${IMAGE_BUILD_ID}" = "${DATA_BUILD_ID}" ] \
    && [ "${IMAGE_EXEC_NAME}" = "${DATA_EXEC_NAME}" ] \
    && [ -f "${DATA_DIR}/${IMAGE_EXEC_NAME}" ]; then
    echo "${DATA_DIR} already holds the miner of this image (${IMAGE_BUILD_ID})."
else
    if [ -n "${DATA_BUILD_ID}" ]; then
        echo "Replacing the miner in ${DATA_DIR}:"
        echo "  installed: ${DATA_BUILD_ID}"
        echo "  image:     ${IMAGE_BUILD_ID}"
    else
        echo "Installing the miner into ${DATA_DIR} (${IMAGE_BUILD_ID})..."
    fi

    # Replace only files shipped by the image.  Explicitly protect the miner's
    # persistent state even if a future upstream archive unexpectedly contains
    # an item with one of these names.
    find "${APP_DIR}" -mindepth 1 -maxdepth 1 | while read -r src; do
        name="$(basename "${src}")"
        case "${name}" in
            settings.json|cookies.jar|cache|log.txt)
                echo "Not replacing persistent miner data: ${name}"
                continue
                ;;
        esac
        rm -rf "${DATA_DIR:?}/${name:?}" || exit 1
        cp -a "${src}" "${DATA_DIR}/${name}" || exit 1
    done || exit 1
fi

if [ ! -f "${DATA_DIR}/.tdm-exec" ]; then
    echo "ERROR: could not install the miner into ${DATA_DIR}."
    exit 1
fi

EXEC_NAME="$(cat "${DATA_DIR}/.tdm-exec")"

if [ ! -f "${DATA_DIR}/${EXEC_NAME}" ]; then
    echo "The miner executable '${EXEC_NAME}' is missing from ${DATA_DIR}."
    exit 1
fi

cd "${DATA_DIR}" || exit 1
[ -x "./${EXEC_NAME}" ] || chmod +x "./${EXEC_NAME}"

# The miner keeps all persistent files next to its executable, which is why the
# packaged build is synchronized into /config rather than run from /opt.
echo "Starting '${EXEC_NAME}' from ${DATA_DIR}..."

# shellcheck disable=SC2086 # TDM_ARGS intentionally holds several arguments.
"./${EXEC_NAME}" ${TDM_ARGS:-} &
APP_PID="$!"

trap 'kill -TERM "${APP_PID}" 2> /dev/null' TERM INT HUP

# wait returns as soon as a signal is caught, which is not necessarily the
# moment the miner terminates.
rc=0
while kill -0 "${APP_PID}" 2> /dev/null; do
    wait "${APP_PID}"
    rc="$?"
done

# Exit codes are documented in the manual.txt shipped with the miner.
case "${rc}" in
    0)
        echo "Twitch Drops Miner exited normally."
        ;;
    1)
        echo "Twitch Drops Miner exited because of a CAPTCHA request or a fatal"
        echo "exception. Open the web interface and complete the login, or check"
        echo "${DATA_DIR}/log.txt for details."
        ;;
    2)
        echo "Twitch Drops Miner rejected its command line arguments."
        echo "Check the value of TDM_ARGS: '${TDM_ARGS:-}'."
        ;;
    3)
        echo "Another instance of Twitch Drops Miner is already running and holds"
        echo "the lock on ${DATA_DIR}. Make sure only one container uses this"
        echo "configuration directory."
        ;;
    4)
        echo "Twitch Drops Miner could not load ${DATA_DIR}/settings.json."
        echo "Fix or remove the file to continue."
        ;;
    130|143)
        echo "Twitch Drops Miner was terminated."
        ;;
    *)
        echo "Twitch Drops Miner exited with code ${rc}."
        ;;
esac

# Selkies' application watchdog restarts this script when it exits.  Pace
# failures so a permanent problem does not become a busy loop hammering Twitch.
if [ "${rc}" -ne 0 ] \
    && [ "${rc}" -ne 130 ] && [ "${rc}" -ne 143 ] \
    && [ "${RESTART_DELAY}" -gt 0 ]; then
    echo "Waiting ${RESTART_DELAY} seconds before exiting, to slow down restarts."
    trap 'kill "${SLEEP_PID}" 2> /dev/null; exit "${rc}"' TERM INT HUP
    sleep "${RESTART_DELAY}" &
    SLEEP_PID="$!"
    wait "${SLEEP_PID}"
fi

exit "${rc}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
