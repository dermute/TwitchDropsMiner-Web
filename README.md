# TwitchDropsMiner-Web

[Twitch Drops Miner][tdm] in a Docker container, with its window streamed to
your browser by [LinuxServer Selkies](https://docs.linuxserver.io/images/docker-baseimage-selkies/).
No VM, desktop, or X server is required on the host. The container keeps mining
unattended, and the interface is available whenever you need it.

The image contains the official Linux build published by [DevilXD][tdm].
Nothing is downloaded when the container starts.

![The miner, running in a browser tab](screenshot.png)

## Quick start

```sh
docker run -d \
    --name twitch-drops-miner \
    --restart unless-stopped \
    -p 3001:3001 \
    --shm-size 1g \
    -v /docker/appdata/twitch-drops-miner:/config \
    -e PUID=1000 \
    -e PGID=1000 \
    -e TZ=Europe/Berlin \
    ghcr.io/dermute/twitchdropsminer-web:latest
```

Then open <https://localhost:3001> or `https://<your-nas>:3001`. Selkies
uses a self-signed certificate by default, so the browser will show a certificate
warning on the first visit.

Or use the included [`docker-compose.yml`](docker-compose.yml):

```sh
docker compose up -d
```

## Security

The session controls a miner authenticated to your Twitch account. Do not expose
it directly to the internet.

This image enables Selkies' single-application hardening by default. Terminals,
passwordless sudo, desktop application launchers, file transfers, sharing,
microphone, audio, and gamepad support are disabled. Clipboard and fullscreen
controls remain available.

For HTTP Basic authentication on a trusted network, add:

```sh
-e CUSTOM_USER=admin \
-e PASSWORD='choose-a-strong-password'
```

The built-in authentication is a convenience, not an internet-facing security
gateway. Use a TLS reverse proxy with strong authentication or a VPN for remote
access. A strict reverse proxy must be configured not to validate the
container's self-signed upstream certificate.

## Migrating from the jlesage/noVNC image

This release intentionally changes the web service and LinuxServer base-image
variables. There are no compatibility aliases.

| Previous interface | Selkies interface |
| --- | --- |
| `http://host:5800` | `https://host:3001` |
| `USER_ID` / `GROUP_ID` | `PUID` / `PGID` |
| `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` | `SELKIES_MANUAL_WIDTH` / `SELKIES_MANUAL_HEIGHT` |
| `WEB_AUTHENTICATION_USERNAME` | `CUSTOM_USER` |
| `WEB_AUTHENTICATION_PASSWORD` | `PASSWORD` |
| `KEEP_APP_RUNNING` | `RESTART_APP` |
| `SECURE_CONNECTION` | Removed; port 3001 is always HTTPS |
| Port 5900 / `VNC_PASSWORD` | Removed; Selkies has no raw VNC endpoint |
| `DARK_MODE` | Removed; it did not affect the miner's own Tk widgets |

Keep the same `/config` mount. The miner remains in `/config/app`, so Twitch
credentials, priorities, settings, and cache migrate in place. Old
jlesage-specific files elsewhere under `/config` are ignored and may be
removed after the new container is working.

## Logging in

The miner uses Twitch's device-code flow, so it does not need a browser inside
the container:

1. Open the Selkies interface. The login tab shows a link and an eight-character
   code.
2. On any device, open <https://www.twitch.tv/activate> and enter the code.
3. The miner detects the session and starts fetching campaigns.

The session is stored in `cookies.jar` inside the `/config` volume, so this
is normally a one-time step.

> [!CAUTION]
> `cookies.jar` grants access to your Twitch account without a password. Treat
> the `/config` volume and its backups as secrets.

> [!TIP]
> Link your Twitch account to the relevant game accounts on the
> [campaigns page](https://www.twitch.tv/drops/campaigns), otherwise most
> campaigns cannot be mined.

## Persistent data

Everything the miner writes remains in the `/config` volume:

| Path | Contents |
| --- | --- |
| `/config/app/` | Miner executable and its persistent files |
| `/config/app/settings.json` | Priority list, mining mode, and GUI settings |
| `/config/app/cookies.jar` | Twitch login session |
| `/config/app/cache/` | Cached campaign and game data |
| `/config/app/log.txt` | Runtime log when `TDM_ARGS` contains `--log` |
| `/config/.config/` | Selkies/Openbox user configuration |

The miner writes next to its executable, so the executable is synchronized from
the immutable image into `/config/app`. On an image update, only files shipped
with the image are replaced. Settings, cookies, cache, and logs are explicitly
preserved.

## Updating

The image is self-contained. Update it by pulling and recreating the container:

```sh
docker compose pull
docker compose up -d
```

A workflow checks DevilXD's rolling `dev-build` release daily and publishes
only when the upstream assets change. A weekly rebuild picks up Alpine and
LinuxServer base-image updates.

Inspect the upstream build carried by an image with:

```sh
docker image inspect ghcr.io/dermute/twitchdropsminer-web:latest \
    --format '{{ index .Config.Labels "io.github.dermute.tdm.upstream-build-id" }}'
```

Once the new image is pulled, its packaged miner replaces the old executable on
container start. Mining progress is maintained by Twitch.

## Configuration

### TwitchDropsMiner-Web

| Variable | Default | Description |
| --- | --- | --- |
| `TDM_ARGS` | `-v` | Miner arguments. `-v` reports warnings, `-vv` info, `-vvvv` debug, and `--log` writes `log.txt`. |
| `TDM_RESTART_DELAY` | `300` | Delay in seconds before Selkies restarts the miner after a failure. |
| `TDM_DATA_DIR` | `/config/app` | Persistent miner installation and data directory. |

### LinuxServer and Selkies

| Variable | Default | Description |
| --- | --- | --- |
| `PUID` / `PGID` | `911` / `911` | Owner of files under `/config`; normally set both to the host user's IDs. |
| `TZ` | `Etc/UTC` | Timezone used by the miner's timestamps. |
| `CUSTOM_USER` | `abc` | Username used when `PASSWORD` enables Basic authentication. |
| `PASSWORD` | unset | Enables Basic authentication when set. |
| `SELKIES_MANUAL_WIDTH` / `SELKIES_MANUAL_HEIGHT` | browser-controlled | Locks the virtual screen to a fixed size when supplied. |
| `RESTART_APP` | `true` | Restarts the launcher if the miner exits. |
| `PIXELFLUX_WAYLAND` | `false` | Keeps the Tk application on the supported X11/Openbox path. |
| `HARDEN_DESKTOP` / `HARDEN_OPENBOX` | `true` | Locks the browser session to the miner. |
| `SELKIES_ENABLE_SHARING` | `false` | Prevents collaborative and view-only session links. |

The Selkies base supports additional settings documented in its
[image reference][baseimage-env]. Overriding the hardening defaults can expose a
terminal with passwordless root access inside the container.

### Ports

| Port | Description |
| --- | --- |
| 3001 | Selkies HTTPS web interface |

The examples publish only port 3001. The Selkies base retains port 3000 as
proxy-only HTTP metadata, but this image does not map it or provide a raw VNC
service.

## Operational notes

- **Only one container per volume.** The miner exits with code 3 if another
  instance holds the lock on the same directory.
- **Use local storage for `/config`.** The lock relies on `fcntl`, which is
  unreliable on NFS and SMB. Use a local bind mount or Docker volume.
- **Do not watch Twitch on the mining account.** Upstream warns that concurrently
  watching with the same account can confuse drop progression.
- **CAPTCHA.** If Twitch requests a CAPTCHA, the miner exits with code 1. The
  container waits `TDM_RESTART_DELAY` before trying again.
- **Shared memory.** The examples allocate 1 GB, matching LinuxServer's Selkies
  recommendations and leaving room for the streamed desktop.

## Architectures

The published image supports `linux/amd64` and `linux/arm64`, matching the
`x86_64` and `aarch64` assets published upstream.

## Building locally

```sh
docker build -t twitchdropsminer-web .
```

Useful build arguments:

- `TDM_RELEASE_TAG` — upstream release tag, default `dev-build`.
- `TDM_BUILD_ID` — upstream build identifier and cache key; CI supplies the
  current release asset IDs.
- `BASEIMAGE_VERSION` — LinuxServer Selkies distro tag, default `alpine324`.
- `DOCKER_IMAGE_VERSION` / `TDM_VERSION` — image and miner version metadata.

The build-time release download is the only miner download. Container startup
does not require GitHub access.

Run the native container smoke test after building:

```sh
tests/container-smoke.sh twitchdropsminer-web
```

## Troubleshooting

**The browser reports a certificate error.** This is expected for Selkies'
self-signed certificate. Accept it on a trusted local network or use a reverse
proxy with a trusted certificate.

**The web interface is available but the miner is absent.** Check
`docker logs twitch-drops-miner`. Selkies' watchdog may be waiting for
`TDM_RESTART_DELAY` after an application failure.

**The miner is older than the image.** Pull and recreate or restart the
container; the packaged build is synchronized only during application startup.

**The interface is slow at a large resolution.** Set
`SELKIES_MANUAL_WIDTH=1280` and `SELKIES_MANUAL_HEIGHT=768`, or reduce the
browser window size.

**Reset everything.** Stop the container and remove its `/config` volume. This
deletes the Twitch session and all settings; the next start performs a clean
installation.

## Repository contents

This repository contains the container definition, launcher and build scripts,
Selkies defaults, project icon, and documentation. The build downloads the
upstream `Twitch.Drops.Miner.Linux.PyInstaller-<arch>.zip` asset unmodified.

## Credits

- [DevilXD/TwitchDropsMiner][tdm] — the miner itself.
- [LinuxServer Selkies][baseimage] — the browser-native desktop, web service,
  Openbox/Xvfb stack, and container lifecycle.
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — the
  underlying web-native remote desktop technology.

## AI attribution

This project was developed with AI assistance.

<div style="display: flex; align-items: center; white-space: nowrap; gap: 0.5rem; padding: 8px;">
  <div style="font-family: IBM Plex Sans; font-weight: 400; font-size: 16px; line-height: 22px; letter-spacing: 0px;">
    <a rel="noopener noreferrer" href="https://aiattribution.github.io/statements/AIA-EAI-Hin-Nr-?model=Opus%205-v1.0" data-cy="recommended-attribution-statement-text" target="_blank" style="font-family: IBM Plex Sans; font-weight: 400; font-size: 16px; line-height: 22px; letter-spacing: 0px;">AIA EAI Hin Nr Opus 5 v1.0 </a>
  </div>
  <div style="display: flex; gap: 0.5rem;">
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <g clip-path="url(#clip0_50_2)">
        <path d="M12 23.5C18.3513 23.5 23.5 18.3513 23.5 12C23.5 5.64873 18.3513 0.5 12 0.5C5.64873 0.5 0.5 5.64873 0.5 12C0.5 18.3513 5.64873 23.5 12 23.5Z" fill="#4E4E4E" stroke="#161616">
        </path>
        <path d="M13.6471 15.6L13.1471 13.94H10.8171L10.3171 15.6H8.77715L11.0771 8.61998H12.9571L15.2271 15.6H13.6471ZM11.9971 9.99998H11.9471L11.1771 12.65H12.7771L11.9971 9.99998Z" fill="white">
        </path>
      </g>
      <defs>
        <clipPath id="clip0_50_2">
          <rect width="24" height="24" fill="white">
          </rect>
        </clipPath>
      </defs>
    </svg>
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M18 17H16.5V16H18V8H16.5V7H18C18.2651 7.0003 18.5193 7.10576 18.7068 7.29323C18.8942 7.4807 18.9997 7.73488 19 8V16C18.9996 16.2651 18.8942 16.5193 18.7067 16.7067C18.5193 16.8942 18.2651 16.9996 18 17Z" fill="#161616">
      </path>
      <path d="M15.5 13C16.0523 13 16.5 12.5523 16.5 12C16.5 11.4477 16.0523 11 15.5 11C14.9477 11 14.5 11.4477 14.5 12C14.5 12.5523 14.9477 13 15.5 13Z" fill="#161616">
      </path>
      <path d="M12 13C12.5523 13 13 12.5523 13 12C13 11.4477 12.5523 11 12 11C11.4477 11 11 11.4477 11 12C11 12.5523 11.4477 13 12 13Z" fill="#161616">
      </path>
      <path d="M8.5 13C9.05228 13 9.5 12.5523 9.5 12C9.5 11.4477 9.05228 11 8.5 11C7.94772 11 7.5 11.4477 7.5 12C7.5 12.5523 7.94772 13 8.5 13Z" fill="#161616">
      </path>
      <path d="M7.5 17H6C5.73488 16.9997 5.4807 16.8942 5.29323 16.7068C5.10576 16.5193 5.0003 16.2651 5 16V8C5.00026 7.73486 5.10571 7.48066 5.29319 7.29319C5.48066 7.10571 5.73486 7.00026 6 7H7.5V8H6V16H7.5V17Z" fill="#161616">
      </path>
      <circle cx="12" cy="12" r="11.5" stroke="#161616">
      </circle>
      <circle cx="12" cy="12" r="11.5" stroke="#161616">
      </circle>
    </svg>
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="12" cy="12" r="11.5" stroke="#161616">
      </circle>
      <path d="M10 6C10.4945 6 10.9778 6.14662 11.3889 6.42133C11.8 6.69603 12.1205 7.08648 12.3097 7.54329C12.4989 8.00011 12.5484 8.50277 12.452 8.98773C12.3555 9.47268 12.1174 9.91814 11.7678 10.2678C11.4181 10.6174 10.9727 10.8555 10.4877 10.952C10.0028 11.0484 9.50011 10.9989 9.04329 10.8097C8.58648 10.6205 8.19603 10.3 7.92133 9.88893C7.64662 9.4778 7.5 8.99445 7.5 8.5C7.5 7.83696 7.76339 7.20107 8.23223 6.73223C8.70107 6.26339 9.33696 6 10 6ZM10 5C9.30777 5 8.63108 5.20527 8.0555 5.58986C7.47993 5.97444 7.03133 6.52107 6.76642 7.16061C6.50151 7.80015 6.4322 8.50388 6.56725 9.18282C6.7023 9.86175 7.03564 10.4854 7.52513 10.9749C8.01461 11.4644 8.63825 11.7977 9.31718 11.9327C9.99612 12.0678 10.6999 11.9985 11.3394 11.7336C11.9789 11.4687 12.5256 11.0201 12.9101 10.4445C13.2947 9.86892 13.5 9.19223 13.5 8.5C13.5 7.57174 13.1313 6.6815 12.4749 6.02513C11.8185 5.36875 10.9283 5 10 5Z" fill="#161616">
      </path>
      <path d="M15 19H14V16.5C14 15.837 13.7366 15.2011 13.2678 14.7322C12.7989 14.2634 12.163 14 11.5 14H8.5C7.83696 14 7.20107 14.2634 6.73223 14.7322C6.26339 15.2011 6 15.837 6 16.5V19H5V16.5C5 15.5717 5.36875 14.6815 6.02513 14.0251C6.6815 13.3687 7.57174 13 8.5 13H11.5C12.4283 13 13.3185 13.3687 13.9749 14.0251C14.6313 14.6815 15 15.5717 15 16.5V19Z" fill="#161616">
      </path>
      <path d="M19.9592 9.99025L19.3932 9.42432L17.938 10.8796L16.4827 9.42432L15.9167 9.99025L17.372 11.4455L15.9167 12.9008L16.4827 13.4667L17.938 12.0115L19.3932 13.4667L19.9592 12.9008L18.5039 11.4455L19.9592 9.99025Z" fill="#161616">
      </path>
    </svg>
  </div>
</div>

## License

The contents of this repository are released under the [MIT license](LICENSE).
Twitch Drops Miner itself is distributed under its own
[MIT license](https://github.com/DevilXD/TwitchDropsMiner/blob/master/LICENSE)
and is redistributed here unmodified, exactly as published upstream.

This project is not affiliated with Twitch, DevilXD, LinuxServer.io, or the Selkies project.

[tdm]: https://github.com/DevilXD/TwitchDropsMiner
[baseimage]: https://github.com/linuxserver/docker-baseimage-selkies
[baseimage-env]: https://docs.linuxserver.io/images/docker-baseimage-selkies/
