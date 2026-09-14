#!/usr/bin/env python3
"""Validate the Unraid template and its icon.

Checks well-formedness plus the mistakes that leave a template *parseable but
unusable*: a self-URL pointing somewhere else, an image reference that is not
this owner's, or a missing required field.

Usage: validate-template.py <owner/repo>
"""
import struct
import sys
import xml.etree.ElementTree as ET

TEMPLATE = "templates/plezy-relay.xml"
PROFILE = "ca_profile.xml"
ICON = "templates/plezy-relay-icon.png"
RAW = "https://raw.githubusercontent.com"
REQUIRED_FIELDS = ("Name", "Repository", "Overview", "Category", "Project", "Icon")


def main() -> int:
    if len(sys.argv) < 2:
        return fail("usage: validate-template.py <owner/repo>")
    slug = sys.argv[1]
    owner = slug.split("/")[0]

    try:
        root = ET.parse(TEMPLATE).getroot()
        profile = ET.parse(PROFILE).getroot()
    except ET.ParseError as exc:
        return fail(f"XML is not well-formed: {exc}")

    # Community Applications rejects a repo whose profile is missing or empty.
    if profile.tag != "CommunityApplications":
        return fail(f"{PROFILE} root must be <CommunityApplications>, got <{profile.tag}>")
    blurb = profile.find("Profile")
    if blurb is None or len((blurb.text or "").strip()) < 40:
        return fail(f"{PROFILE} needs a non-trivial <Profile> description")

    if root.tag != "Container":
        return fail(f"root element must be <Container>, got <{root.tag}>")

    problems = []

    for field in REQUIRED_FIELDS:
        node = root.find(field)
        if node is None or not (node.text or "").strip():
            problems.append(f"<{field}> is missing or empty")

    expect_url = f"{RAW}/{slug}/main/{TEMPLATE}"
    if text(root, "TemplateURL") != expect_url:
        problems.append(f"<TemplateURL> should be {expect_url}, got {text(root, 'TemplateURL')!r}")

    expect_icon = f"{RAW}/{slug}/main/{ICON}"
    if text(root, "Icon") != expect_icon:
        problems.append(f"<Icon> should be {expect_icon}, got {text(root, 'Icon')!r}")

    expect_image = f"ghcr.io/{owner.lower()}/plezy-relay"
    if not text(root, "Repository").startswith(expect_image):
        problems.append(f"<Repository> should start with {expect_image}, got {text(root, 'Repository')!r}")

    # The relay is a WebSocket service with no web interface; a populated WebUI
    # renders a button that goes nowhere.
    webui = root.find("WebUI")
    if webui is not None and (webui.text or "").strip():
        problems.append("<WebUI> must be empty - the relay has no web interface")

    tags = [t.text for t in root.findall("./Branch/Tag")]
    if "latest" not in tags:
        problems.append(f"<Branch> list must offer 'latest', got {tags}")

    configs = {c.get("Target"): c for c in root.findall("Config")}
    if "8080" not in configs:
        problems.append("no <Config Type=\"Port\"> for 8080")
    if "/data" not in configs:
        problems.append("no <Config Type=\"Path\"> for /data")

    problems += check_icon()

    if problems:
        for p in problems:
            print(f"::error::{p}")
        return 1

    print(f"template ok: {len(configs)} config entries, {len(tags)} selectable tags {tags}")
    return 0


def text(root, tag: str) -> str:
    node = root.find(tag)
    return (node.text or "").strip() if node is not None else ""


def check_icon() -> list:
    try:
        data = open(ICON, "rb").read()
    except OSError as exc:
        return [f"cannot read {ICON}: {exc}"]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return [f"{ICON} is not a PNG"]
    width, height = struct.unpack(">II", data[16:24])
    out = []
    if width != height:
        out.append(f"icon should be square, got {width}x{height}")
    if not 64 <= width <= 512:
        out.append(f"icon should be 64-512px, got {width}px")
    if not out:
        print(f"icon ok: {width}x{height}, {len(data)} bytes")
    return out


def fail(message: str) -> int:
    print(f"::error::{message}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
