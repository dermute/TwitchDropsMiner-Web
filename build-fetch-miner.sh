#!/bin/sh
#
# Download the upstream Twitch Drops Miner Linux build into a directory.
#
# This runs while the image is built.  The Linux (PyInstaller) build published
# by DevilXD is downloaded from GitHub and unpacked, together with two files
# recording which build it is and what its executable is called, which is what
# the container uses to install it into /config.
#

set -u

UPSTREAM_REPO="${TDM_UPSTREAM_REPO:-DevilXD/TwitchDropsMiner}"
TAG=dev-build
DEST=
ARCH=

usage() {
    echo "usage: $(basename "$0") --dest DIR [--tag TAG] [--arch ARCH]

Download the upstream Twitch Drops Miner Linux build into DIR.

Options:
  --dest DIR    Directory to download the build into.  Required.
  --tag TAG     Upstream release tag to download.  Default: ${TAG}
  --arch ARCH   Architecture to download (x86_64, aarch64, amd64, arm64).
                Default: the architecture of the running machine.
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

# Locate the executable.  It is the only executable file the archive ships, but
# fall back to the largest file in case that ever changes.
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

mkdir -p "${DEST}" || die "could not create ${DEST}."
cp -a "${SRC_DIR}"/. "${DEST}"/ || die "could not copy the build into ${DEST}."
chmod +x "${DEST}/${EXEC_NAME}" || die "could not make ${EXEC_NAME} executable."

printf '%s\n' "${EXEC_NAME}" > "${DEST}/.tdm-exec" \
    || die "could not write ${DEST}/.tdm-exec."
printf '%s' "${BUILD_ID}" > "${DEST}/.tdm-build-id" \
    || die "could not write ${DEST}/.tdm-build-id."

log "Downloaded '${EXEC_NAME}' (${ARCH}), build ${BUILD_ID}."

# vim:ft=sh:ts=4:sw=4:et:sts=4
