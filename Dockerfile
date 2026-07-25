#
# Twitch Drops Miner Dockerfile
#
# https://github.com/dermute/TwitchDropsMiner-Web
#

ARG BASEIMAGE_VERSION=ubuntu-24.04-v4.12.6

FROM jlesage/baseimage-gui:${BASEIMAGE_VERSION}

# Version of this Docker image, provided by the build workflow.
ARG DOCKER_IMAGE_VERSION=
# Upstream release the miner is downloaded from.  "dev-build" is the rolling
# release DevilXD publishes the current builds to.
ARG TDM_RELEASE_TAG=dev-build

WORKDIR /tmp

# Install dependencies.  The miner is a PyInstaller bundle that carries its own
# Python and Tk, but still links against the X libraries of the system.
RUN \
    add-pkg \
        # Needed to download the upstream release.
        curl \
        ca-certificates \
        unzip \
        jq \
        # Needed by the miner itself.
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

# Generate and install favicons.  The icon is the one of the upstream project.
COPY icon.png /tmp/app-icon.png
RUN \
    install_app_icon.sh "file:///tmp/app-icon.png" && \
    rm -f /tmp/app-icon.png

# Set internal environment variables.
RUN \
    set-cont-env APP_NAME "Twitch Drops Miner" && \
    set-cont-env APP_VERSION "${TDM_RELEASE_TAG}" && \
    set-cont-env DOCKER_IMAGE_VERSION "${DOCKER_IMAGE_VERSION}" && \
    set-cont-env DISABLE_GLX 1 && \
    true

# Set public environment variables.
ENV \
    # The miner is meant to run unattended, so restart it when it exits.
    KEEP_APP_RUNNING=1 \
    # Where the miner and its data live.  Must be under /config to be persisted.
    TDM_DATA_DIR=/config/app \
    # Upstream release the miner is downloaded from and kept in sync with.
    TDM_RELEASE_TAG="${TDM_RELEASE_TAG}" \
    TDM_UPSTREAM_REPO=DevilXD/TwitchDropsMiner \
    # Keep the miner up-to-date with the upstream release.
    TDM_AUTO_UPDATE=1 \
    TDM_UPDATE_CHECK_INTERVAL=86400 \
    TDM_UPDATE_RESTART=1 \
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
