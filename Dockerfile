#
# TwitchDropsMiner-Web Dockerfile
#
# https://github.com/dermute/TwitchDropsMiner-Web
#

ARG BASEIMAGE_VERSION=alpine324

#
# Download the upstream Twitch Drops Miner build.
#
# This stage runs on the architecture of the build machine and only downloads a
# file, so building the arm64 image does not need emulation for it.
#
FROM --platform=${BUILDPLATFORM} alpine:3.24 AS miner

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
    apk add --no-cache \
        ca-certificates \
        curl \
        findutils \
        jq \
        unzip

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
FROM ghcr.io/linuxserver/baseimage-selkies:${BASEIMAGE_VERSION}

# Version of this Docker image, provided by the build workflow.
ARG DOCKER_IMAGE_VERSION=
# Version of the miner in this image, provided by the build workflow.
ARG TDM_VERSION=dev-build
# Identifier of the upstream build in this image, recorded as a label below.
ARG TDM_BUILD_ID=

# Install dependencies.  The miner is a PyInstaller bundle that carries its own
# Python and Tk, but still links against the X libraries of the system.
RUN \
    apk add --no-cache \
        # The miner validates the certificate of every Twitch connection.
        ca-certificates \
        libx11 \
        libxext \
        libxrender \
        libxinerama \
        libxft \
        fontconfig \
        zlib \
        # The upstream PyInstaller bundle targets glibc; Alpine uses musl.
        gcompat \
        # Needed by the optional tray icon support of the miner.
        libayatana-appindicator \
        # Needed by the Openbox XDG autostart helper.
        py3-xdg \
        # Fonts for the miner labels, including emoji.
        font-dejavu \
        font-noto-emoji

# Add the application launcher and LinuxServer branding.
COPY rootfs/ /
COPY --from=miner /opt/tdm/app /opt/tdm/app

# Install the upstream project icon for the Selkies web client.
COPY icon.png /usr/share/selkies/www/icon.png

ENV \
    # Identify this as a third-party image built on a LinuxServer base.
    LSIO_FIRST_PARTY=false \
    # Selkies page and sidebar branding.
    TITLE="Twitch Drops Miner" \
    SELKIES_UI_TITLE="Twitch Drops Miner" \
    # The miner is an X11/Tk application.
    PIXELFLUX_WAYLAND=false \
    # This image is a locked single-application session.
    START_DOCKER=false \
    HARDEN_DESKTOP=true \
    HARDEN_OPENBOX=true \
    RESTART_APP=true \
    SELKIES_ENABLE_SHARING=false \
    SELKIES_AUDIO_ENABLED=false \
    SELKIES_MICROPHONE_ENABLED=false \
    SELKIES_GAMEPAD_ENABLED=false \
    NO_GAMEPAD=true \
    SELKIES_SECOND_SCREEN=false \
    SELKIES_UI_SHOW_CORE_BUTTONS=false \
    SELKIES_UI_SIDEBAR_SHOW_AUDIO_SETTINGS=false \
    SELKIES_UI_SIDEBAR_SHOW_GAMEPADS=false \
    SELKIES_UI_SIDEBAR_SHOW_SHARING=false \
    SELKIES_UI_SIDEBAR_SHOW_GAMING_MODE=false \
    SELKIES_CLIPBOARD_ENABLED=true \
    SELKIES_UI_SIDEBAR_SHOW_FULLSCREEN=true \
    # Where the miner and its data live.  Must be under /config to be persisted.
    TDM_DATA_DIR=/config/app \
    # Command line arguments passed to the miner.
    TDM_ARGS=-v \
    # Delay before the miner is restarted after it failed.
    TDM_RESTART_DELAY=300

# Define mountable directories.
VOLUME ["/config"]

# Supported published interface. The base retains proxy-only port 3000 metadata.
EXPOSE 3001

# Metadata.  The upstream build id is what the build workflow reads back off the
# published image, to know whether a newer miner has been released.
LABEL \
      build_version="TwitchDropsMiner-Web version:- ${DOCKER_IMAGE_VERSION:-unknown} Miner:- ${TDM_VERSION}" \
      maintainer="dermute" \
      org.opencontainers.image.title="TwitchDropsMiner-Web" \
      org.opencontainers.image.description="Twitch Drops Miner streamed with LinuxServer Selkies" \
      org.opencontainers.image.source="https://github.com/dermute/TwitchDropsMiner-Web" \
      org.opencontainers.image.documentation="https://github.com/dermute/TwitchDropsMiner-Web#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="dermute/TwitchDropsMiner-Web" \
      io.github.dermute.tdm.upstream-build-id="${TDM_BUILD_ID}" \
      io.github.dermute.tdm.version="${TDM_VERSION}" \
      org.label-schema.name="TwitchDropsMiner-Web" \
      org.label-schema.description="Docker container for Twitch Drops Miner" \
      org.label-schema.version="${DOCKER_IMAGE_VERSION:-}" \
      org.label-schema.vcs-url="https://github.com/dermute/TwitchDropsMiner-Web" \
      org.label-schema.schema-version="1.0"
