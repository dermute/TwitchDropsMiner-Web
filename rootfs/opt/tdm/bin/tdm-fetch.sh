#!/bin/sh
#
# Install the upstream Twitch Drops Miner Linux build into a directory.
#
# The Linux (PyInstaller) build published by DevilXD is downloaded from GitHub
# and unpacked into the destination directory.  Files the miner creates itself
# (settings.json, cookies.jar, cache/, ...) are left untouched, which makes this
# script usable both to seed the image at build time and to update an existing
# installation at runtime.
#
# Exit codes:
#    0  the destination is already up-to-date, nothing was done
#   10  a build was downloaded and installed
#    1  an error occurred
#

set -u

UPSTREAM_REPO="${TDM_UPSTREAM_REPO:-DevilXD/TwitchDropsMiner}"
TAG="${TDM_RELEASE_TAG:-dev-build}"
DEST=
ARCH=
CHECK_ONLY=0

BUILD_ID_FILE=.tdm-build-id
EXEC_FILE=.tdm-exec

usage() {
    echo "usage: $(basename "$0") --dest DIR [--tag TAG] [--arch ARCH] [--check-only]

Install the upstream Twitch Drops Miner Linux build into DIR.

Options:
  --dest DIR    Directory to install the build into.  Required.
  --tag TAG     Upstream release tag to install.  Default: ${TAG}
  --arch ARCH   Architecture to install (x86_64, aarch64, amd64, arm64).
                Default: the architecture of the running machine.
  --check-only  Do not download anything, only report whether an update is
                available (exit code 10) or not (exit code 0).
"
    exit 2
}

log() {
    echo "$*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dest) DEST="${2:-}"; shift 2 || usage ;;
        --tag) TAG="${2:-}"; shift 2 || usage ;;
        --arch) ARCH="${2:-}"; shift 2 || usage ;;
        --check-only) CHECK_ONLY=1; shift ;;
        -h|--help) usage ;;
        *) echo "unknown argument: $1" >&2; usage ;;
    esac
done

[ -n "${DEST}" ] || usage
[ -n "${TAG}" ] || usage

[ -n "${ARCH}" ] || ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64) ARCH=x86_64 ;;
    aarch64|arm64) ARCH=aarch64 ;;
    *) die "unsupported architecture: ${ARCH}" ;;
esac

ASSET_NAME="Twitch.Drops.Miner.Linux.PyInstaller-${ARCH}.zip"
API_URL="https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG}"

# Requests to the GitHub API are rate limited per IP address when they are made
# anonymously.  A token is not required, but is honoured when provided.
api_get() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 15 \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "$1"
    else
        curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 15 \
            -H "Accept: application/vnd.github+json" \
            "$1"
    fi
}

log "Looking up '${ASSET_NAME}' from ${UPSTREAM_REPO} (release '${TAG}')..."
RELEASE_JSON="$(api_get "${API_URL}")" \
    || die "could not query the GitHub API for release '${TAG}'."

ASSET_INFO="$(
    printf '%s' "${RELEASE_JSON}" | jq -r --arg name "${ASSET_NAME}" '
        [.assets[]? | select(.name == $name)][0]
        | if . == null then empty else "\(.id)\t\(.updated_at)\t\(.browser_download_url)" end
    '
)" || die "could not parse the response from the GitHub API."

[ -n "${ASSET_INFO}" ] \
    || die "release '${TAG}' does not provide an asset named '${ASSET_NAME}'."

ASSET_ID="$(printf '%s' "${ASSET_INFO}" | cut -f1)"
ASSET_UPDATED="$(printf '%s' "${ASSET_INFO}" | cut -f2)"
ASSET_URL="$(printf '%s' "${ASSET_INFO}" | cut -f3)"

# The rolling "dev-build" release keeps the same tag while its assets are
# replaced, so the asset id and its upload time identify the build.
BUILD_ID="${TAG} ${ASSET_ID} ${ASSET_UPDATED}"
CURRENT_BUILD_ID="$(cat "${DEST}/${BUILD_ID_FILE}" 2> /dev/null || true)"

if [ "${BUILD_ID}" = "${CURRENT_BUILD_ID}" ] && [ -f "${DEST}/${EXEC_FILE}" ]; then
    log "Already running the latest build (uploaded ${ASSET_UPDATED})."
    exit 0
fi

if [ "${CHECK_ONLY}" -eq 1 ]; then
    log "A new build is available (uploaded ${ASSET_UPDATED})."
    exit 10
fi

TMP_DIR="$(mktemp -d)" || die "could not create a temporary directory."
# shellcheck disable=SC2064 # The directory name is known now, expand it now.
trap "rm -rf '${TMP_DIR}'" EXIT INT TERM

log "Downloading the build uploaded ${ASSET_UPDATED}..."
curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 15 \
    -o "${TMP_DIR}/tdm.zip" "${ASSET_URL}" \
    || die "could not download ${ASSET_URL}."

unzip -q "${TMP_DIR}/tdm.zip" -d "${TMP_DIR}/unpacked" \
    || die "could not unpack the downloaded archive."

# The archive holds a single directory named after the application.
SRC_DIR="$(find "${TMP_DIR}/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "${SRC_DIR}" ] || die "unexpected layout of the downloaded archive."

mkdir -p "${DEST}" || die "could not create ${DEST}."

# Replacing the executable in place would fail with "Text file busy" while the
# miner is running, so the old file is unlinked first: a running process keeps
# using the inode it already opened, and the next start picks up the new file.
find "${SRC_DIR}" -mindepth 1 -maxdepth 1 | while read -r src; do
    name="$(basename "${src}")"
    rm -rf "${DEST:?}/${name:?}" || exit 1
    cp -a "${src}" "${DEST}/${name}" || exit 1
done || die "could not install the build into ${DEST}."

# Locate the executable that was just installed.  It is the only executable file
# the archive ships, but fall back to the largest file in case that ever changes.
EXEC_NAME="$(
    find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -type f -perm -u+x -printf '%f\n' \
        2> /dev/null | head -n 1
)"
if [ -z "${EXEC_NAME}" ]; then
    EXEC_NAME="$(
        find "${SRC_DIR}" -mindepth 1 -maxdepth 1 -type f -printf '%s\t%f\n' \
            | sort -rn | head -n 1 | cut -f2
    )"
    [ -n "${EXEC_NAME}" ] || die "could not find the miner executable in the archive."
fi
chmod +x "${DEST}/${EXEC_NAME}" || die "could not make ${EXEC_NAME} executable."

printf '%s\n' "${EXEC_NAME}" > "${DEST}/${EXEC_FILE}" \
    || die "could not write ${DEST}/${EXEC_FILE}."
printf '%s' "${BUILD_ID}" > "${DEST}/${BUILD_ID_FILE}" \
    || die "could not write ${DEST}/${BUILD_ID_FILE}."

log "Installed '${EXEC_NAME}' (${ARCH}) into ${DEST}."
exit 10

# vim:ft=sh:ts=4:sw=4:et:sts=4
