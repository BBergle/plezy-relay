# plezy-relay

Up-to-date Docker images for the **Plezy Watch Together relay server**, plus an
Unraid template.

[Plezy](https://github.com/edde746/plezy) is a cross-platform Plex/Jellyfin/Emby
client. Its Watch Together feature syncs playback between viewers through a relay
server, and upstream supports pointing clients at your own. The relay source lives
in the `server/` directory of the Plezy repo — but upstream never publishes a built
image, so self-hosting it means cloning the repo and running `docker build` yourself.

This repository does that for you, on every Plezy release.

```
ghcr.io/bbergle/plezy-relay:latest
```

`linux/amd64` and `linux/arm64`. **Unofficial** — see [NOTICE.md](NOTICE.md).

## Quick start

```bash
docker run -d --name plezy-relay \
  -p 8080:8080 \
  -v /mnt/user/appdata/plezy-relay:/data \
  --restart unless-stopped \
  ghcr.io/bbergle/plezy-relay:latest
```

Then in Plezy, set the Watch Together relay to `ws://YOUR-SERVER-IP:8080/relay`.

There is **no web interface** — this is a WebSocket service. To check it is alive:

```bash
curl http://YOUR-SERVER-IP:8080/health   # -> ok
```

## Unraid

The template is [`templates/plezy-relay.xml`](templates/plezy-relay.xml). It is not in
Community Applications yet, so install it by copying it onto the flash drive.

On the Unraid box — *Terminal* in the web UI, or SSH — run:

```bash
curl -L -o /boot/config/plugins/dockerMan/templates-user/my-plezy-relay.xml \
  https://raw.githubusercontent.com/BBergle/plezy-relay/main/templates/plezy-relay.xml
```

Then Docker → *Add Container* → open the **Template** dropdown and pick
**plezy-relay** (it appears under the user templates section) → *Apply*.

> There is nowhere in current Unraid to paste a template URL. The Add Container
> "Template" control is a dropdown that lists templates already on the flash
> drive, and the old Docker Settings → "Template Repositories" field was removed
> in 6.10. Guides that tell you to paste a URL predate that change.

Once installed, the template's **Repository** dropdown lets you pick `latest` or
pin a specific Plezy version.

## Tags

| Tag | Meaning |
|---|---|
| `latest` | The newest Plezy release |
| `2.19.1` | Exactly the relay shipped with Plezy 2.19.1 — never moves |
| `2.19` | Newest patch within 2.19 |
| `2` | Newest release in the 2.x line |
| `sha-5a7e096` | Built from that upstream commit |

**A version tag names the Plezy release the relay came from, not a relay version.**
The relay has no version number of its own; it negotiates a wire protocol version
(currently 2, with the legacy version 0 still accepted) per connection.

Upstream's advice is to **deploy the updated relay before updating your clients**.
Pinning to the version your clients run is the safe play; `latest` is fine if you
update the relay first.

Images start at Plezy **2.19.1**. Earlier releases were not built, so if you need
to pair a relay with an older client you will have to build it yourself from that
tag of the Plezy repository.

## Configuration

Defaults work out of the box. Everything below is optional.

| Environment variable | Purpose |
|---|---|
| `TRUSTED_PROXY_CIDRS` | Comma-separated CIDRs whose `X-Forwarded-For` is trusted, e.g. `172.17.0.0/16`. Set this **only** behind a reverse proxy. |
| `OAUTH_BASE_URL` | Public base URL, enabling the MyAnimeList/AniList OAuth proxy at `/auth/*`. Unset, `/auth/*` returns 503. Watch Together does not need it. |
| `MAL_CLIENT_ID` | MyAnimeList OAuth client ID |
| `ANILIST_CLIENT_ID` / `ANILIST_CLIENT_SECRET` | AniList OAuth credentials |

> `TRUSTED_PROXY_CIDRS` is strict: **an unparseable value makes the relay exit
> immediately** with `invalid TRUSTED_PROXY_CIDRS`. If the container refuses to
> start after you touched it, that is why. Leave it blank when in doubt.

The relay's other settings are command-line flags, not environment variables, and
all default sensibly inside the container (`-addr :8080`, `-log-dir /data/logs`,
`-poster-dir /data/posters`, `-state-file /data/rooms.json`). Override them with
Unraid's *Post Arguments* field, or by appending them to `docker run`.

`/data` holds room state, uploaded client logs, and Discord poster artifacts.
Mapping it is what lets an in-progress Watch Together session survive a restart.

### Exposing it to the internet

The relay speaks **plain HTTP/WebSocket and has no TLS**. Do not port-forward it
directly. Put a reverse proxy in front, terminate TLS there, use `wss://`, and set
`TRUSTED_PROXY_CIDRS` to your proxy's network so rate limiting sees real client IPs.

## Staying up to date

New Plezy releases are picked up automatically, so a new image is normally
available within a day of a release. You do not need to watch this repository.

If you want your container to follow along on its own, install the **CA Auto
Update Applications** plugin on Unraid, enable it for `plezy-relay`, and stay on
the `latest` tag. Otherwise update it whenever you update your Plezy clients —
relay first.

A few things worth knowing about what you are pulling:

- **It is upstream's build, not a fork.** Every image is produced from Plezy's own
  unmodified `server/Dockerfile` at that release tag. No Plezy source is copied,
  patched, or vendored here.
- **Broken builds do not reach you.** Before any tag is published, the image has
  to start, answer `/health`, and complete a real relay handshake. A bad upstream
  commit fails the build rather than becoming your `latest`.
- **Pinned tags never move.** When a Plezy release does not change the relay at
  all, the new version tag is pointed at the existing image instead of rebuilding,
  so the digest you pinned stays exactly the same.

To check which upstream commit an image came from:

```bash
docker inspect ghcr.io/bbergle/plezy-relay:latest \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
```

## Licence

GPL-3.0, matching upstream. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
