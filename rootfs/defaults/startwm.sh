#!/bin/sh

# Keep LinuxServer's X11/Openbox startup behavior, but do not discard the
# session's stdout and stderr. The miner is unattended, so its diagnostics must
# remain available through docker logs.
if command -v nvidia-smi > /dev/null 2>&1 \
    && ls -A /dev/dri 2> /dev/null \
    && [ "${DISABLE_ZINK:-false}" = "false" ]; then
    export LIBGL_KOPPER_DRI2=1
    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export GALLIUM_DRIVER=zink
fi

exec dbus-launch --exit-with-session /usr/bin/openbox-session
