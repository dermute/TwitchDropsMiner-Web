#!/bin/sh
#
# Exercise migration, HTTPS/authentication, hardening, and restart behavior.
#

set -eu

IMAGE="${1:-twitchdropsminer-web:smoke}"
TEST_ROOT="$(mktemp -d)"
MIGRATION_CONTAINER="tdm-migration-$$"
RUNTIME_CONTAINER="tdm-runtime-$$"
MIGRATION_VOLUME="tdm-migration-$$"
RUNTIME_VOLUME="tdm-runtime-$$"
SMOKE_UID="$(id -u)"
SMOKE_GID="$(id -g)"

# LinuxServer deliberately ignores PUID/PGID 0. Use an ordinary account when
# this test is launched by root.
if [ "${SMOKE_UID}" -eq 0 ]; then
    SMOKE_UID=1000
    SMOKE_GID=1000
fi

cleanup() {
    docker rm -f "${MIGRATION_CONTAINER}" "${RUNTIME_CONTAINER}" \
        > /dev/null 2>&1 || true
    docker volume rm -f "${MIGRATION_VOLUME}" "${RUNTIME_VOLUME}" \
        > /dev/null 2>&1 || true
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
    echo "ERROR: $*" >&2
    docker logs "${MIGRATION_CONTAINER}" 2> /dev/null || true
    docker logs "${RUNTIME_CONTAINER}" 2> /dev/null || true
    exit 1
}

wait_for_migration() {
    count=0
    while [ "${count}" -lt 120 ]; do
        if docker exec "${MIGRATION_CONTAINER}" sh -c \
            'test -s /config/app/.tdm-build-id &&
             test "$(cat /config/app/.tdm-build-id)" != legacy-build'; then
            return 0
        fi
        count=$((count + 1))
        sleep 1
    done
    return 1
}

wait_for_https() {
    port="$1"
    count=0
    while [ "${count}" -lt 120 ]; do
        if curl -ksSf -u smoke:secret "https://127.0.0.1:${port}/" \
            > "${TEST_ROOT}/index.html" 2> /dev/null; then
            return 0
        fi
        count=$((count + 1))
        sleep 1
    done
    return 1
}

miner_pid() {
    docker exec "${RUNTIME_CONTAINER}" sh -c '
        exec_name="$(cat /config/app/.tdm-exec)"
        pattern="${exec_name%% (*}"
        pgrep -o -u abc -f "$pattern"
    '
}

docker volume create "${MIGRATION_VOLUME}" > /dev/null
docker volume create "${RUNTIME_VOLUME}" > /dev/null

echo "Checking Alpine runtime base..."
docker run --rm --entrypoint /bin/sh "${IMAGE}" -c '
    test -f /etc/alpine-release
    case "$(cat /etc/alpine-release)" in
        3.24.*) ;;
        *) exit 1 ;;
    esac
' || fail "image is not based on Alpine 3.24"

echo "Checking migration of an existing /config/app..."
before_hashes="$(
    docker run --rm \
        --entrypoint /bin/sh \
        -e "SEED_UID=${SMOKE_UID}" \
        -e "SEED_GID=${SMOKE_GID}" \
        -v "${MIGRATION_VOLUME}:/config" \
        "${IMAGE}" -c '
            mkdir -p /config/app/cache
            printf "%s\n" legacy-build > /config/app/.tdm-build-id
            printf "%s\n" "{\"smoke\":\"settings\"}" > /config/app/settings.json
            printf "%s\n" smoke-cookie > /config/app/cookies.jar
            printf "%s\n" smoke-cache > /config/app/cache/marker
            printf "%s\n" smoke-log > /config/app/log.txt
            chown -R "$SEED_UID:$SEED_GID" /config
            cd /config/app
            sha256sum settings.json cookies.jar cache/marker log.txt
        '
)"

docker run -d \
    --name "${MIGRATION_CONTAINER}" \
    --shm-size 1g \
    -e "PUID=${SMOKE_UID}" \
    -e "PGID=${SMOKE_GID}" \
    -e TDM_ARGS=--smoke-invalid-argument \
    -e TDM_RESTART_DELAY=1 \
    -v "${MIGRATION_VOLUME}:/config" \
    "${IMAGE}" > /dev/null

wait_for_migration || fail "the packaged miner was not synchronized"

after_hashes="$(
    docker exec "${MIGRATION_CONTAINER}" sh -c '
        cd /config/app
        sha256sum settings.json cookies.jar cache/marker log.txt
    '
)"
[ "${before_hashes}" = "${after_hashes}" ] \
    || fail "persistent miner data changed during migration"

docker rm -f "${MIGRATION_CONTAINER}" > /dev/null
printf '%s\n' "Migration preserved settings, cookies, cache, and logs."

echo "Checking Selkies HTTPS, authentication, hardening, and restart..."
docker run -d \
    --name "${RUNTIME_CONTAINER}" \
    --shm-size 1g \
    -e "PUID=${SMOKE_UID}" \
    -e "PGID=${SMOKE_GID}" \
    -e CUSTOM_USER=smoke \
    -e PASSWORD=secret \
    -e TDM_RESTART_DELAY=1 \
    -p 127.0.0.1::3001 \
    -v "${RUNTIME_VOLUME}:/config" \
    "${IMAGE}" > /dev/null

port_mapping="$(docker port "${RUNTIME_CONTAINER}" 3001/tcp)"
https_port="${port_mapping##*:}"
[ -n "${https_port}" ] || fail "Docker did not publish Selkies port 3001"

wait_for_https "${https_port}" || fail "Selkies HTTPS did not become ready"

unauthenticated_status="$(
    curl -ks -o /dev/null -w '%{http_code}' "https://127.0.0.1:${https_port}/"
)"
[ "${unauthenticated_status}" = 401 ] \
    || fail "unauthenticated Selkies request returned ${unauthenticated_status}, expected 401"


docker exec "${RUNTIME_CONTAINER}" test -s /usr/share/selkies/www/icon.png \
    || fail "Selkies icon was not installed"

count=0
while [ "${count}" -lt 120 ]; do
    if docker exec "${RUNTIME_CONTAINER}" test -d /config/app \
        && [ -n "$(miner_pid 2> /dev/null || true)" ]; then
        break
    fi
    count=$((count + 1))
    sleep 1
done
[ "${count}" -lt 120 ] || fail "miner application did not become ready"

app_owner="$(docker exec "${RUNTIME_CONTAINER}" stat -c %u /config/app)"
[ "${app_owner}" = "${SMOKE_UID}" ] \
    || fail "/config/app is owned by UID ${app_owner}, expected ${SMOKE_UID}"

docker exec "${RUNTIME_CONTAINER}" sh -c '
    test "$TITLE" = "Twitch Drops Miner"
    test "$SELKIES_UI_TITLE" = "Twitch Drops Miner"
    test "$HARDEN_DESKTOP" = true
    test "$HARDEN_OPENBOX" = true
    test "$START_DOCKER" = false
    test "$SELKIES_ENABLE_SHARING" = false
    test "$SELKIES_AUDIO_ENABLED" = false
    test "$SELKIES_MICROPHONE_ENABLED" = false
    test "$SELKIES_GAMEPAD_ENABLED" = false
    test "$NO_GAMEPAD" = true
    test ! -x /usr/bin/sudo
' || fail "single-application hardening is not active"


docker logs "${RUNTIME_CONTAINER}" 2>&1 \
    | grep -q "'command_enabled': (False, False)" \
    || fail "Selkies command handling is not disabled"

docker logs "${RUNTIME_CONTAINER}" 2>&1 \
    | grep -q "'ui_sidebar_show_files': (False, False)" \
    || fail "Selkies file-transfer UI is not disabled"

old_pid=""
count=0
while [ "${count}" -lt 60 ]; do
    old_pid="$(miner_pid 2> /dev/null || true)"
    [ -n "${old_pid}" ] && break
    count=$((count + 1))
    sleep 1
done
[ -n "${old_pid}" ] || fail "miner process did not start as user abc"

killed=false
count=0
while [ "${count}" -lt 60 ]; do
    old_pid="$(miner_pid 2> /dev/null || true)"
    if [ -n "${old_pid}" ] && docker exec "${RUNTIME_CONTAINER}" kill -KILL "${old_pid}" > /dev/null 2>&1; then
        killed=true
        break
    fi
    count=$((count + 1))
    sleep 1
done
[ "${killed}" = true ] || fail "miner process could not be killed for restart test"

new_pid=""
count=0
while [ "${count}" -lt 60 ]; do
    new_pid="$(miner_pid 2> /dev/null || true)"
    if [ -n "${new_pid}" ] && [ "${new_pid}" != "${old_pid}" ]; then
        break
    fi
    count=$((count + 1))
    sleep 1
done
if [ -z "${new_pid}" ] || [ "${new_pid}" = "${old_pid}" ]; then
    fail "Selkies watchdog did not restart the miner"
fi

docker logs "${RUNTIME_CONTAINER}" 2>&1 \
    | grep -q 'Waiting 1 seconds before exiting' \
    || fail "restart delay was not visible in the container log"

printf '%s\n' "Selkies smoke test passed."
