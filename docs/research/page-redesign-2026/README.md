# Hash Fleet page approval gallery

Open `index.html` locally. No server, remote fonts, scripts, analytics or credentials are required.

`current/` contains original simulator/loopback XCTest screenshots. `proposals/` contains original provider-generated images. No image pixels were changed during packaging. `manifest.json` records SHA-256 checksums, per-page context, source revision and generation briefs.

Rebuild from the original scratch artifacts:

```sh
python3 docs/research/page-redesign-2026/build_gallery.py \
  --captures "$HOME/.jcode/scratch/axe-page-capture/screenshots" \
  --generated "$HOME/.jcode/generated-images"
```

The gallery is an approval artifact, not an implemented redesign. Read `docs/PAGE-REDESIGN-BRIEFS-2026-09-10.md` for known concept corrections and safety requirements. All route groups have a source screenshot. Generic endpoint variants and native system pickers are explicitly distinguished from app-designed pages.

Static validation checks all links, fragment targets, image signatures, hashes and coverage. Browser interaction could not be exercised in the current harness: browser launch and file opening were suppressed. Do not report this as a browser-tested gallery.
