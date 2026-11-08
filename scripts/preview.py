#!/usr/bin/env python3
"""Render every markdown file to GitHub-styled HTML for local preview.

Builds a `.preview/` tree that mirrors the repo layout (README.md ->
.previews/README.html, docs/cli.md -> .preview/docs/cli.html, ...) plus an
index page. Renders through GitHub's GFM API so the output matches github.com
exactly, rewrites internal `.md` links to `.html` so navigation works locally,
and symlinks `media/` so the README's screenshots resolve.

The `.preview/` directory is gitignored, so this never leaks into a commit.

Usage:
    python3 scripts/preview.py            # build .preview/
    python3 scripts/preview.py --open     # also open the index in a browser
"""

import argparse
import json
import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".preview")
GFM_API = "https://api.github.com/markdown"

# The same styling GitHub's markdown body uses, just enough to look right.
TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;line-height:1.5;color:#1f2328;background:#fff;margin:0}}
.markdown-body{{max-width:980px;margin:24px auto;padding:24px 40px;box-sizing:border-box}}
.markdown-body img{{max-width:100%;height:auto}}
pre{{background:#f6f8fa;padding:16px;border-radius:6px;overflow:auto}}
code{{font-size:85%}}
blockquote{{border-left:3px solid #d0d7de;margin:0;padding-left:16px;color:#656d76}}
table{{border-collapse:collapse;display:block;overflow:auto}} td,th{{border:1px solid #d0d7de;padding:6px 12px}}
p{{margin:0 0 16px}}
a{{color:#0969da}}
</style></head><body><article class="markdown-body">{body}</article></body></html>"""


def render(text):
    """Render markdown through GitHub's GFM API."""
    req = urllib.request.Request(
        GFM_API,
        data=json.dumps({"mode": "gfm", "text": text}).encode(),
        headers={"Content-Type": "application/json"},
    )
    return urllib.request.urlopen(req).read().decode()


def source_files():
    """Every markdown file, as (source_path, out_html_path) pairs."""
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # Skip the preview output, git, and anything hidden.
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        if ".git" in os.path.relpath(dirpath, ROOT).split(os.sep):
            continue
        for name in filenames:
            if not name.endswith(".md"):
                continue
            src = os.path.join(dirpath, name)
            relpath = os.path.relpath(src, ROOT)
            html = os.path.join(OUT, relpath[:-3] + ".html")
            files.append((src, html))
    return sorted(files)


def rewrite_links(html):
    """Rewrite internal `*.md` links to `*.html` so local preview navigates."""
    return re.sub(r'href="([^"]+)\.md(#[^"]*)?"', r'href="\1.html\2"', html)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--open", action="store_true", help="open the index in a browser")
    args = parser.parse_args()

    os.makedirs(OUT, exist_ok=True)

    # Symlink media/ so the README's images resolve from .preview/README.html.
    media_link = os.path.join(OUT, "media")
    if not os.path.islink(media_link) and not os.path.exists(media_link):
        os.symlink(os.path.join(ROOT, "media"), media_link)

    entries = []
    for src, html in source_files():
        with open(src) as fh:
            text = fh.read()
        body = rewrite_links(render(text))
        rel = os.path.relpath(html, OUT)
        title = rel[:-5].replace(os.sep, " / ") + " — omaset"
        os.makedirs(os.path.dirname(html), exist_ok=True)
        with open(html, "w") as fh:
            fh.write(TEMPLATE.format(title=title, body=body))
        entries.append((rel, title))
        print(f"  {rel}")

    # Index page linking every rendered page.
    links = "\n".join(
        f'<li><a href="{rel}">{title}</a></li>' for rel, title in entries
    )
    index = TEMPLATE.format(
        title="omaset docs — preview",
        body=f"<h1>omaset docs</h1><ul>{links}</ul>",
    )
    with open(os.path.join(OUT, "index.html"), "w") as fh:
        fh.write(index)
    print(f"  index.html  ({len(entries)} pages)")

    if args.open:
        import subprocess

        subprocess.run(["xdg-open", os.path.join(OUT, "index.html")])


if __name__ == "__main__":
    main()
