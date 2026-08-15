#!/usr/bin/env python3
"""Resamples the app icon master into the sizes each platform's launcher needs.

The master is `app/assets/images/Zibo Games 512.png`; everything under
`app/android`, `app/ios`, `app/macos` and `app/windows` that carries the icon is
derived from it, so a new icon means replacing the master and re-running this:

    python3 tool/icon/generate_platform_icons.py

Its 114 px sibling in the same directory is the Amazon Appstore listing's small icon. This script
neither reads nor writes it, so a new icon means replacing both files by hand and re-running this for
everything else.

It needs Pillow (`pip install pillow`) and is deliberately not wired into
`tool/verify.sh` or CI: the outputs are committed, so a build never depends on
having an image library installed. The check that matters is reading the
regenerated PNGs in the diff, not re-deriving them on every run.

Two platform rules are encoded here rather than left to whoever runs it:

- iOS icons are written without an alpha channel. App Store submission rejects a
  bundle whose icons have one, and the failure arrives at upload time, long
  after the change that introduced it.
- The 1024 px sizes iOS and macOS ask for are larger than the master, so they
  are the one upscale in the set. Lanczos on a flat-colour icon holds up, but
  replacing the master with a 1024 px original would remove the compromise.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the message is the whole point
    sys.exit("Pillow is required: pip install pillow")

REPO = Path(__file__).resolve().parents[2]
MASTER = REPO / "app" / "assets" / "images" / "Zibo Games 512.png"

ANDROID = REPO / "app" / "android" / "app" / "src" / "main" / "res"
IOS = REPO / "app" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS = REPO / "app" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WINDOWS = REPO / "app" / "windows" / "runner" / "resources"

# Density buckets, in the launcher icon size each one expects.
ANDROID_MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Filenames as `AppIcon.appiconset/Contents.json` refers to them: the name
# carries the point size and the scale, the pixel size is their product.
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

# macOS names the files by pixel size and lets Contents.json map them to the
# point size and scale that want them, so a 256 serves both 128@2x and 256@1x.
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# One .ico holds every size Windows picks from: 16 for the title bar, 256 for
# the large view in Explorer, the rest for the sizes in between.
WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]


def scaled(master: Image.Image, size: int) -> Image.Image:
    """The master at `size` px square, or the master itself when it already is."""
    if size == master.width:
        return master.copy()
    return master.resize((size, size), Image.LANCZOS)


def write(image: Image.Image, path: Path, *, alpha: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGBA" if alpha else "RGB").save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(REPO)} ({image.width}px)")


def main() -> None:
    if not MASTER.is_file():
        sys.exit(f"Master icon not found: {MASTER.relative_to(REPO)}")
    master = Image.open(MASTER).convert("RGBA")
    if master.width != master.height:
        sys.exit(f"Master icon is not square: {master.width}x{master.height}")
    print(f"Master: {MASTER.relative_to(REPO)} ({master.width}px)")

    print("Android")
    for density, size in ANDROID_MIPMAPS.items():
        write(scaled(master, size), ANDROID / f"mipmap-{density}" / "ic_launcher.png")

    print("iOS")
    for name, size in IOS_ICONS.items():
        write(scaled(master, size), IOS / name, alpha=False)

    print("macOS")
    for size in MACOS_SIZES:
        write(scaled(master, size), MACOS / f"app_icon_{size}.png")

    print("Windows")
    ico = WINDOWS / "app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    largest = scaled(master, max(WINDOWS_SIZES))
    largest.save(ico, "ICO", sizes=[(s, s) for s in WINDOWS_SIZES])
    print(f"  {ico.relative_to(REPO)} ({', '.join(str(s) for s in WINDOWS_SIZES)}px)")


if __name__ == "__main__":
    main()
