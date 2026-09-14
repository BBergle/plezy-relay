# Notices

## Unofficial build

This repository is **not affiliated with, endorsed by, or maintained by the Plezy
project or its authors**. It is a community-run build pipeline.

It contains no Plezy source code. The GitHub Actions workflows check out
[edde746/plezy](https://github.com/edde746/plezy) at a release tag and build the
unmodified `server/Dockerfile` found there. The published image is the output of
upstream's own build recipe, with nothing added, patched, or removed.

Report problems with the *container or template* to this repository's issue
tracker. Report problems with the *relay itself* upstream — but please confirm
first that the same behaviour occurs when building `server/` by hand, so upstream
does not receive bug reports caused by this packaging.

## Licensing

Plezy is licensed under the **GNU General Public License v3.0**. The relay binary
inside the published image is a work derived from that source, so it is
distributed under the GPL-3.0 as well; a copy is in [`LICENSE`](LICENSE).

Corresponding source for any published image is the `edde746/plezy` repository at
the git ref recorded in that image's `org.opencontainers.image.revision` label, and
in the `sha-<short>` tag published alongside every release tag:

```
docker inspect ghcr.io/bbergle/plezy-relay:2.19.1 \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'
```

The build scripts, workflows, and Unraid template in this repository are also
offered under the GPL-3.0 for consistency.

## Icon

`templates/plezy-relay-icon.png` is Plezy's application icon, taken from `assets/plezy.png`
upstream and downscaled to 256×256 for Unraid. It is used to identify the
application, and remains the property of the Plezy project.
