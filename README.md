# TwitchDropsMiner-Web

[Twitch Drops Miner][tdm] in a Docker container, with its window served to your
web browser. No VM, no desktop, no X server on the host — just a container that
keeps mining 24/7 and a tab you open when you want to look at it.

The container downloads the official Linux build published by [DevilXD][tdm],
keeps it up-to-date on its own, and runs it on a virtual screen that is streamed
to the browser over [noVNC][novnc]. The GUI plumbing is provided by
[jlesage/baseimage-gui][baseimage].

![The miner, running in a browser tab](screenshot.png)

## Quick start

```sh
docker run -d \
    --name twitch-drops-miner \
    --restart unless-stopped \
    -p 5800:5800 \
    -v /docker/appdata/twitch-drops-miner:/config \
    -e TZ=Europe/Berlin \
    ghcr.io/dermute/twitchdropsminer-web:latest
```

Then open <http://localhost:5800> (or `http://<your-nas>:5800`).

Or with Docker Compose — see [`docker-compose.yml`](docker-compose.yml):

```sh
docker compose up -d
```

## Logging in

The miner logs in with Twitch's device code flow, so no browser is needed inside
the container:

1. Open the web interface. The login tab shows a link and an 8 character code.
2. On any device, go to <https://www.twitch.tv/activate> and enter the code.
3. The miner picks up the session and starts fetching campaigns.

The session is stored in `cookies.jar` inside your `/config` volume, so this is
a one-time step.

> [!CAUTION]
> `cookies.jar` grants access to your Twitch account without a password. Treat
> the `/config` volume — and any backup of it — as a secret.

> [!TIP]
> Link your Twitch account to the game accounts on the
> [campaigns page](https://www.twitch.tv/drops/campaigns), otherwise most
> campaigns cannot be mined.

## Where your data lives

Everything the miner writes is inside the `/config` volume:

| Path                      | Contents                                        |
| ------------------------- | ----------------------------------------------- |
| `/config/app/`            | The miner itself, plus all files it creates      |
| `/config/app/settings.json` | Priority list, mining mode, all GUI settings   |
| `/config/app/cookies.jar` | Twitch login session                             |
| `/config/app/cache/`      | Cached campaign and game data                    |
| `/config/app/log.txt`     | Runtime log, only written when `TDM_ARGS` has `--log` |
| `/config/xdg/`            | XDG directories of the container user            |

The miner stores its files next to its own executable, which is why the
executable lives in the volume rather than in the image.

## Staying up-to-date

The image does not ship a copy of the miner. Upstream publishes its current
builds to a rolling `dev-build` release, and the container follows it directly:

- On the first start, the current upstream build is downloaded into the volume.
- On every following start, it is updated to the current upstream build.
- While the container runs, it checks once a day (`TDM_UPDATE_CHECK_INTERVAL`)
  and restarts the miner when a new build was published. Mining resumes right
  after — progress lives on Twitch's side, not in the container.

So the miner stays current without ever pulling a new image. The image is
rebuilt weekly anyway, to pick up base image updates.

Set `TDM_AUTO_UPDATE=0` to freeze the miner at whatever build is installed in
the volume. The container needs to reach GitHub on its very first start,
otherwise there is nothing to run.

## Configuration

### This image

| Variable                    | Default              | Description                                                                                   |
| --------------------------- | -------------------- | --------------------------------------------------------------------------------------------- |
| `TDM_ARGS`                  | `-v`                 | Arguments for the miner. `-v` reports warnings, `-vv` info, `-vvvv` debug; `--log` also writes `log.txt`. |
| `TDM_AUTO_UPDATE`           | `1`                  | Update the miner from the upstream release.                                                    |
| `TDM_UPDATE_CHECK_INTERVAL` | `86400`              | Seconds between update checks while running. `0` only checks at start.                         |
| `TDM_UPDATE_RESTART`        | `1`                  | Restart the miner right away when an update was installed.                                     |
| `TDM_RELEASE_TAG`           | `dev-build`          | Upstream release tag to follow.                                                                |
| `TDM_UPSTREAM_REPO`         | `DevilXD/TwitchDropsMiner` | Upstream repository to fetch builds from.                                                |
| `TDM_RESTART_DELAY`         | `300`                | Seconds to wait before restarting after the miner failed.                                      |
| `TDM_DATA_DIR`              | `/config/app`        | Where the miner is installed.                                                                  |
| `GITHUB_TOKEN`              | (unset)              | Optional, raises the GitHub API rate limit used for update checks.                             |

### Base image

The most useful ones — the base image supports
[many more][baseimage-env]:

| Variable                       | Default    | Description                                                        |
| ------------------------------ | ---------- | ------------------------------------------------------------------ |
| `USER_ID` / `GROUP_ID`         | `1000`     | Owner of the files in `/config`.                                    |
| `TZ`                           | `Etc/UTC`  | Timezone, affects the timestamps shown by the miner.                |
| `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` | `1920` / `1080` | Size of the virtual screen. `1280x768` is plenty for the miner. |
| `WEB_AUTHENTICATION`           | `0`        | Put a login in front of the web interface.                          |
| `WEB_AUTHENTICATION_USERNAME` / `WEB_AUTHENTICATION_PASSWORD` | | Credentials for it. |
| `SECURE_CONNECTION`            | `0`        | Serve the web interface over HTTPS.                                 |
| `VNC_PASSWORD`                 | (unset)    | Password for VNC clients on port 5900.                              |
| `KEEP_APP_RUNNING`             | `1`        | Restart the miner when it exits. Set to `0` to stop the container instead. |
| `DARK_MODE`                    | `0`        | Dark GTK/Qt theme. The miner draws its own Tk widgets, so this changes little. |

### Ports

| Port | Description                                            |
| ---- | ------------------------------------------------------ |
| 5800 | Web interface. This is the one you want.               |
| 5900 | Raw VNC, for a native client. Not published by default. |

## Notes

- **Only one container per volume.** The miner takes a lock on its directory and
  exits with code 3 if a second instance uses the same `/config`.
- **Use local storage for `/config`.** The lock relies on `fcntl` locking, which
  is unreliable on NFS and SMB mounts — a common trap on a NAS. A local Docker
  volume or a directory on local disk is fine.
- **Do not watch Twitch on the mining account.** Upstream warns that watching a
  stream in a browser with the same account confuses the drop progression.
- **Do not expose port 5800 to the internet as-is.** Anyone who reaches it
  controls a browser-visible session that is logged into your Twitch account. Use
  `WEB_AUTHENTICATION`, a reverse proxy with authentication, or a VPN.
- **CAPTCHA.** If Twitch asks for a CAPTCHA during login, the miner exits with
  code 1. The container waits `TDM_RESTART_DELAY` seconds and tries again rather
  than looping; log in again through the web interface when that happens.

## Architectures

`linux/amd64` and `linux/arm64`, matching the `x86_64` and `aarch64` builds
upstream publishes.

## Building it yourself

```sh
docker build -t twitch-drops-miner .
```

Useful build arguments:

- `TDM_RELEASE_TAG` — upstream release the container downloads the miner from.
  Default `dev-build`.
- `BASEIMAGE_VERSION` — tag of `jlesage/baseimage-gui` to build on.
- `DOCKER_IMAGE_VERSION` — version string baked into the image labels.

The build itself does not touch the upstream project: nothing is downloaded from
it until a container starts.

## Troubleshooting

**The web interface is up but the window is empty.** The miner is probably
restarting. Check `docker logs twitch-drops-miner`.

**`could not check for a newer build`.** The container could not reach the GitHub
API, or ran into its anonymous rate limit. The already installed build keeps
running; set `GITHUB_TOKEN` if you hit the rate limit regularly.

**Reset everything.** Stop the container and delete the `/config` volume. The
next start reinstalls the miner and asks you to log in again.

## What this repository actually contains

A Dockerfile, a handful of shell scripts, and a favicon. The only thing taken
from the upstream project at runtime is the release asset
`Twitch.Drops.Miner.Linux.PyInstaller-<arch>.zip` — a single executable and its
`manual.txt` — downloaded unmodified from the `dev-build` release. The favicon is
converted from the upstream `icons/pickaxe.ico`.

## Credits

- [DevilXD/TwitchDropsMiner][tdm] — the actual miner. This repository only
  packages it; all mining logic, the GUI, and the icon are theirs.
- [jlesage/docker-baseimage-gui][baseimage] — the X server, noVNC and supervisor
  plumbing that make the GUI reachable from a browser.

Built with [Claude Opus 5](https://claude.com/claude-code).

## License

The contents of this repository are released under the [MIT license](LICENSE).
Twitch Drops Miner itself is distributed under its own
[MIT license](https://github.com/DevilXD/TwitchDropsMiner/blob/master/LICENSE)
and is downloaded, unmodified, from the upstream releases.

This project is not affiliated with Twitch, DevilXD, or jlesage.

[tdm]: https://github.com/DevilXD/TwitchDropsMiner
[baseimage]: https://github.com/jlesage/docker-baseimage-gui
[baseimage-env]: https://github.com/jlesage/docker-baseimage-gui#environment-variables
[novnc]: https://github.com/novnc/noVNC
