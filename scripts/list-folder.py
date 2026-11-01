#!/usr/bin/env python3
"""List a folder for a dock stack as JSON.

Usage: list-folder.py FOLDER [SORT] [LIMIT]

SORT is one of:
  name      natural, case-insensitive name order
  kind      by type (folders first, then extension), then name
  modified  newest modification first (default)
  added     newest first by when the entry landed in the folder; Linux has
            no "date added", and the inode change time (ctime) is the closest
            stand-in: moving or downloading a file into a folder sets it
  size      largest first (folders count as 0)

LIMIT caps the items returned (default 16, at most 1000).

Prints {"count": N, "items": [...first LIMIT...], "folder": FOLDER,
"failed": BOOL}. `failed` is true when the folder is missing or cannot be
opened, so a caller never reports it as empty. Hidden entries are skipped. At most MAX_SCAN visible entries are read
("truncated": true when the folder holds more). Each file carries "thumb":
a preview image path, preferring a freedesktop thumbnail a file manager
already rendered (~/.cache/thumbnails), then the file itself for small
PNG/JPEG/WebP images only (SVG and GIF are never decoded in the shell),
else "". The output is always valid JSON, even for a missing folder.
"""

import hashlib
import json
import os
import re
import sys
import time

DEFAULT_LIMIT = 16
MAX_LIMIT = 1000
MAX_SCAN = 20000                      # entries read before giving up
PREVIEW_EXT = {".png", ".jpg", ".jpeg", ".webp"}
MAX_PREVIEW_BYTES = 20 * 1024 * 1024  # larger originals are not previewed
THUMB_DIRS = [
    os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "thumbnails", size)
    # Smallest that still looks sharp in a grid tile first.
    for size in ("large", "normal", "x-large", "xx-large")
]
SORTS = ("name", "kind", "modified", "added", "size")

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"}
VIDEO_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi"}
AUDIO_EXT = {".mp3", ".flac", ".wav", ".ogg", ".m4a"}
ARCHIVE_EXT = {".zip", ".tar", ".gz", ".xz", ".7z", ".rar"}
TEXT_EXT = {".txt", ".md", ".json", ".qml", ".py", ".cpp", ".js", ".lua", ".rs", ".go", ".html", ".css"}


def human_size(n):
    if n < 1024:
        return "%d B" % n
    if n < 1024 ** 2:
        return "%.1f KB" % (n / 1024)
    if n < 1024 ** 3:
        return "%.1f MB" % (n / 1024 ** 2)
    return "%.1f GB" % (n / 1024 ** 3)


def human_age(ts):
    diff = time.time() - ts
    if diff < 60:
        return "Just now"
    if diff < 3600:
        return "%dm ago" % (diff // 60)
    if diff < 86400:
        return "%dh ago" % (diff // 3600)
    return "%dd ago" % (diff // 86400)


def icon_for(ext, is_dir):
    if is_dir:
        return "folder"
    if ext in IMAGE_EXT:
        return "image-x-generic"
    if ext in VIDEO_EXT:
        return "video-x-generic"
    if ext in AUDIO_EXT:
        return "audio-x-generic"
    if ext in ARCHIVE_EXT:
        return "package-x-generic"
    if ext == ".pdf":
        return "application-pdf"
    if ext in TEXT_EXT:
        return "text-x-generic"
    return "application-x-executable"


def thumbnail_for(path):
    """A thumbnail some file manager already made, per the freedesktop
    thumbnail spec: the MD5 of the file URI names it."""
    uri = "file://" + "/".join(quote_segment(s) for s in path.split("/"))
    name = hashlib.md5(uri.encode("utf-8")).hexdigest() + ".png"
    for directory in THUMB_DIRS:
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate):
            return candidate
    return ""


def quote_segment(segment):
    from urllib.parse import quote
    # Names that are not valid UTF-8 arrive as surrogate escapes; the URI
    # needs their raw bytes percent-encoded.
    return quote(segment.encode("utf-8", "surrogateescape"), safe="!$&'()*+,;=:@-._~")


def natural_key(name):
    return [int(part) if part.isdecimal() else part for part in re.split(r"(\d+)", name.casefold())]


def main():
    folder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else ""
    sort = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] in SORTS else "modified"
    try:
        limit = max(1, min(MAX_LIMIT, int(sys.argv[3]))) if len(sys.argv) > 3 else DEFAULT_LIMIT
    except ValueError:
        limit = DEFAULT_LIMIT

    entries = []
    truncated = False
    failed = not (folder and os.path.isdir(folder))
    if not failed:
        try:
            with os.scandir(folder) as scan:
                for entry in scan:
                    if entry.name.startswith("."):
                        continue
                    if len(entries) >= MAX_SCAN:
                        truncated = True
                        break
                    try:
                        st = entry.stat()
                        is_dir = entry.is_dir()
                    except OSError:
                        continue
                    ext = "" if is_dir else os.path.splitext(entry.name)[1].lower()
                    size = 0 if is_dir else st.st_size
                    entries.append({
                        "name": entry.name,
                        "path": entry.path,
                        "isDir": is_dir,
                        "isImage": ext in IMAGE_EXT,
                        "size": human_size(size),
                        "time": human_age(st.st_mtime),
                        "mtime": st.st_mtime,
                        "icon": icon_for(ext, is_dir),
                        "_ext": ext,
                        "_bytes": size,
                        "_ctime": st.st_ctime,
                    })
        except OSError:
            # A missing, moved or unreadable folder is not an empty one: the
            # popup says so instead of claiming there is nothing inside.
            failed = True

    if sort == "name":
        entries.sort(key=lambda e: natural_key(e["name"]))
    elif sort == "kind":
        entries.sort(key=lambda e: (not e["isDir"], e["_ext"], natural_key(e["name"])))
    elif sort == "added":
        entries.sort(key=lambda e: e["_ctime"], reverse=True)
    elif sort == "size":
        entries.sort(key=lambda e: (e["_bytes"], e["mtime"]), reverse=True)
    else:
        entries.sort(key=lambda e: e["mtime"], reverse=True)

    items = []
    for e in entries[:limit]:
        item = {k: v for k, v in e.items() if not k.startswith("_")}
        if not e["isDir"]:
            # A cached thumbnail is a small PNG; decoding the original photo
            # (often megabytes) is the fallback.
            previewable = e["_ext"] in PREVIEW_EXT and e["_bytes"] <= MAX_PREVIEW_BYTES
            item["thumb"] = thumbnail_for(e["path"]) or (e["path"] if previewable else "")
        items.append(item)
    print(json.dumps({"count": len(entries), "items": items, "folder": folder,
                      "sort": sort, "truncated": truncated, "failed": failed}))


if __name__ == "__main__":
    main()
