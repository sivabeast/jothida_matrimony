#!/usr/bin/env python3
"""Regenerate ONLY the Android launcher icon (home screen / app drawer).

This touches nothing inside the app: the in-app logo `assets/images/app_logo.png`
and every widget/splash/login/header that uses it are left exactly as they are.
It only rewrites the Android launcher resources from a single source image.

What it writes:
  - Legacy icons:        android/app/src/main/res/mipmap-<d>/ic_launcher.png
  - Adaptive foreground: android/app/src/main/res/drawable-<d>/ic_launcher_foreground.png
  - Adaptive icon XML:   mipmap-anydpi-v26/ic_launcher.xml (full-bleed foreground;
                         the launcher applies its own circular/rounded mask)

Usage:
    python3 tool/generate_launcher_icon.py [SOURCE_IMAGE]

SOURCE_IMAGE defaults to assets/icons/launcher_icon.png. Supported: PNG/JPG.
Requires Pillow (pip install pillow). No Flutter/Android SDK needed.
"""
import os
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(ROOT, "assets", "icons", "launcher_icon.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# Standard Android launcher densities.
LEGACY_PX = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND_PX = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

ADAPTIVE_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <background android:drawable="@color/ic_launcher_background"/>\n'
    '  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
    "</adaptive-icon>\n"
)


def load_center_square(path: str) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    s = min(w, h)
    left, top = (w - s) // 2, (h - s) // 2
    return im.crop((left, top, left + s, top + s))


def main() -> None:
    src_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.exists(src_path):
        sys.exit(
            f"ERROR: source image not found:\n  {src_path}\n\n"
            "Save the new launcher image there (or pass a path) and re-run."
        )

    src = load_center_square(src_path)
    print(f"source: {src_path}  {src.size[0]}x{src.size[1]}")

    for d, px in LEGACY_PX.items():
        out = os.path.join(RES, f"mipmap-{d}", "ic_launcher.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        src.resize((px, px), Image.LANCZOS).save(out)
        print(f"  legacy     mipmap-{d}/ic_launcher.png  {px}px")

    for d, px in FOREGROUND_PX.items():
        out = os.path.join(RES, f"drawable-{d}", "ic_launcher_foreground.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        src.resize((px, px), Image.LANCZOS).save(out)
        print(f"  foreground drawable-{d}/ic_launcher_foreground.png  {px}px")

    xml_out = os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml")
    os.makedirs(os.path.dirname(xml_out), exist_ok=True)
    with open(xml_out, "w", encoding="utf-8") as f:
        f.write(ADAPTIVE_XML)
    print("  adaptive   mipmap-anydpi-v26/ic_launcher.xml")

    print("\nDONE — launcher icon regenerated. In-app logos/branding untouched.")
    print("Rebuild/reinstall the app to see the new home-screen icon.")


if __name__ == "__main__":
    main()
