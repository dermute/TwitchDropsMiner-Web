#!/bin/sh
#
# Install the Twitch Drops Miner build shipped with this image into /config.
#
# The miner keeps all its persistent files (settings.json, cookies.jar, cache/,
# log.txt) next to its own executable, so the executable has to live in the
# volume.  Only the files that came with the image are replaced here, everything
# the miner created is left alone.
#

set -u

APP_DIR=/opt/tdm/app
DATA_DIR="${TDM_DATA_DIR:-/config/app}"
RUN_DIR=/var/run/tdm

mkdir -p "${DATA_DIR}" || exit 1
mkdir -p "${RUN_DIR}" || exit 1

# A stale pid file from a container that was killed would confuse startapp.sh.
rm -f "${RUN_DIR}/app.pid"

if [ ! -f "${APP_DIR}/.tdm-exec" ]; then
    echo "ERROR: this image does not contain a Twitch Drops Miner build."
    exit 1
fi

IMAGE_BUILD_ID="$(cat "${APP_DIR}/.tdm-build-id")"
DATA_BUILD_ID="$(cat "${DATA_DIR}/.tdm-build-id" 2> /dev/null || true)"

if [ "${IMAGE_BUILD_ID}" = "${DATA_BUILD_ID}" ] && [ -f "${DATA_DIR}/.tdm-exec" ]; then
    echo "${DATA_DIR} already holds the miner of this image (${IMAGE_BUILD_ID})."
else
    if [ -n "${DATA_BUILD_ID}" ]; then
        echo "Replacing the miner in ${DATA_DIR}:"
        echo "  installed: ${DATA_BUILD_ID}"
        echo "  image:     ${IMAGE_BUILD_ID}"
    else
        echo "Installing the miner into ${DATA_DIR} (${IMAGE_BUILD_ID})..."
    fi

    find "${APP_DIR}" -mindepth 1 -maxdepth 1 | while read -r src; do
        name="$(basename "${src}")"
        rm -rf "${DATA_DIR:?}/${name:?}" || exit 1
        cp -a "${src}" "${DATA_DIR}/${name}" || exit 1
    done

    if [ ! -f "${DATA_DIR}/.tdm-exec" ]; then
        echo "ERROR: could not install the miner into ${DATA_DIR}."
        exit 1
    fi
fi

take-ownership "${DATA_DIR}"
take-ownership "${RUN_DIR}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
