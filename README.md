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

The template is [`unraid/plezy-relay.xml`](unraid/plezy-relay.xml). It is not in
Community Applications yet, so install it one of these two ways.

**Add Container → Template URL.** Docker tab → *Add Container*, and paste into the
Template field:

```
https://raw.githubusercontent.com/BBergle/plezy-relay/main/unraid/plezy-relay.xml
```

**Or drop the file on the flash drive** (more reliable, survives a browser that
refuses to fetch the URL):

```bash
curl -L -o /boot/config/plugins/dockerMan/templates-user/my-plezy-relay.xml \
  https://raw.githubusercontent.com/BBergle/plezy-relay/main/unraid/plezy-relay.xml
```

Then Docker → *Add Container* → pick **plezy-relay** from the Template dropdown.

> Unraid removed the old "Template Repositories" settings field in 6.10. If a guide
> tells you to paste a repo URL there, it is out of date.

The template's **Repository** dropdown lets you pick `latest` or pin a specific
Plezy version.

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

Images exist for Plezy **1.24.0 and later only** — that is the release where
`server/Dockerfile` first appeared upstream. There is no backfill: this repository
started at 2.19.1 and publishes each release from then on.

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

## How it stays current

A scheduled workflow checks for new Plezy releases daily.

Most Plezy releases do not touch `server/` at all — across the 54 tags that contain
it, there are only 13 distinct versions of that directory. So the workflow compares
the release's `server/` git tree against what has already been built; when it is
unchanged, the new version tags are added to the **existing manifest** rather than
rebuilding. Same digest, and it finishes in seconds.

When `server/` genuinely changed, the image is rebuilt, and before any tag is
published the build is smoke-tested: the container must come up, answer `/health`,
and complete a real relay handshake advertising `authenticatedResume`
([`scripts/ws_probe.py`](scripts/ws_probe.py)). A broken upstream commit does not
become your `latest`.

Nothing in this repository is a copy of Plezy. Workflows check out upstream at the
target tag and build its unmodified Dockerfile, so there is nothing here to fall
out of date.

To publish a release by hand, run the **Watch for Plezy releases** workflow with a
`release` input (and `force_rebuild` if you need to redo one).

## Repository layout

```
.github/workflows/build.yml           reusable: build + smoke test + push one ref
.github/workflows/release-watch.yml   daily: detect, build or re-tag, record
.github/workflows/template-lint.yml   XML, icon, and shell checks
scripts/plan-release.sh               decides none / build / re-tag
scripts/render-template.sh            regenerates the template version dropdown
scripts/mirror-template.sh            copies the template to BBergle/unraid-templates
scripts/ws_probe.py                   relay protocol smoke test
state/builds.json                     what has been published, and tree -> tag map
unraid/plezy-relay.xml                the Unraid template
```

`state/builds.json` is the source of truth for what has shipped. Deleting an entry
and re-running the workflow republishes that release.

## Licence

GPL-3.0, matching upstream. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
