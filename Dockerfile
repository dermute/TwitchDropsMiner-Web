#
# TwitchDropsMiner-Web Dockerfile
#
# https://github.com/dermute/TwitchDropsMiner-Web
#

ARG BASEIMAGE_VERSION=ubuntu-24.04-v4.12.6

#
# Download the upstream Twitch Drops Miner build.
#
# This stage runs on the architecture of the build machine and only downloads a
# file, so building the arm64 image does not need emulation for it.
#
FROM --platform=${BUILDPLATFORM} debian:trixie-slim AS miner

# Architecture of the image being built, provided by BuildKit.
ARG TARGETARCH
# Upstream release to take the miner from.  "dev-build" is the rolling release
# DevilXD publishes the current builds to.
ARG TDM_RELEASE_TAG=dev-build
ARG TDM_UPSTREAM_REPO=DevilXD/TwitchDropsMiner
# Identifier of the upstream build to install.  The build workflow sets it to
# the current one, which is what makes a rebuild pick up a newer upstream build
# instead of reusing the cached layer below.
ARG TDM_BUILD_ID=

RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        findutils \
        jq \
        unzip && \
    rm -rf /var/lib/apt/lists/*

COPY build-fetch-miner.sh /usr/local/bin/fetch-miner.sh

# The token is optional and only avoids the anonymous GitHub API rate limit.  It
# is mounted as a build secret, so that it does not end up in the image.
RUN \
    --mount=type=secret,id=github_token \
    echo "Installing upstream build: ${TDM_BUILD_ID:-current}" && \
    GITHUB_TOKEN="$(cat /run/secrets/github_token 2> /dev/null || true)" \
    TDM_UPSTREAM_REPO="${TDM_UPSTREAM_REPO}" \
    /usr/local/bin/fetch-miner.sh \
        --dest /opt/tdm/app \
        --tag "${TDM_RELEASE_TAG}" \
        --arch "${TARGETARCH}"

#
# Build the image.
#
FROM jlesage/baseimage-gui:${BASEIMAGE_VERSION}

# Version of this Docker image, provided by the build workflow.
ARG DOCKER_IMAGE_VERSION=
# Version of the miner in this image, provided by the build workflow.
ARG TDM_VERSION=dev-build

WORKDIR /tmp

# Install dependencies.  The miner is a PyInstaller bundle that carries its own
# Python and Tk, but still links against the X libraries of the system.
RUN \
    add-pkg \
        # The miner validates the certificate of every Twitch connection, and
        # the base image ships no CA bundle.
        ca-certificates \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libxinerama1 \
        libxft2 \
        libfontconfig1 \
        zlib1g \
        # Needed by the (optional) tray icon support of the miner.
        libayatana-appindicator3-1 \
        gir1.2-ayatanaappindicator3-0.1 \
        # A font is needed.  The miner labels some of its columns and states
        # with emoji, which DejaVu does not cover.
        fonts-dejavu-core \
        fonts-noto-color-emoji

# Add files.
COPY rootfs/ /
COPY --from=miner /opt/tdm/app /opt/tdm/app

# Generate and install favicons.  The icon is the one of the upstream project.
COPY icon.png /tmp/app-icon.png
RUN \
    install_app_icon.sh "file:///tmp/app-icon.png" && \
    rm -f /tmp/app-icon.png

# Set internal environment variables.
RUN \
    set-cont-env APP_NAME "Twitch Drops Miner" && \
    set-cont-env APP_VERSION "${TDM_VERSION}" && \
    set-cont-env DOCKER_IMAGE_VERSION "${DOCKER_IMAGE_VERSION}" && \
    set-cont-env DISABLE_GLX 1 && \
    true

# Set public environment variables.
ENV \
    # The miner is meant to run unattended, so restart it when it exits.
    KEEP_APP_RUNNING=1 \
    # Where the miner and its data live.  Must be under /config to be persisted.
    TDM_DATA_DIR=/config/app \
    # Command line arguments passed to the miner.
    TDM_ARGS=-v \
    # Delay before the miner is restarted after it failed.
    TDM_RESTART_DELAY=300

# Define mountable directories.
VOLUME ["/config"]

# Expose ports.
#   - 5800: Web interface.
#   - 5900: VNC.
EXPOSE 5800 5900

# Metadata.
LABEL \
      org.label-schema.name="TwitchDropsMiner-Web" \
      org.label-schema.description="Docker container for Twitch Drops Miner" \
      org.label-schema.version="${DOCKER_IMAGE_VERSION:-}" \
      org.label-schema.vcs-url="https://github.com/dermute/TwitchDropsMiner-Web" \
      org.label-schema.schema-version="1.0"
