#!/usr/bin/env python3
"""Restore the themed launcher icon resource dropped by Godot's Android exporter.

Godot 4.7 writes the monochrome adaptive icon into icon.xml but leaves the
packaged resources.arsc pointing at a missing themed_icon.xml. Copying the
compiled icon.xml to that path keeps aapt2 and Android 13 themed icons intact.
Run after exporting the APK; the APK is re-signed with the debug keystore.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / "build" / "android" / "fenghuo-gorge-debug.apk"
BUILD_TOOLS = Path(r"D:\AppCache\Android-Sdk\build-tools\36.0.0")
ZIPALIGN = BUILD_TOOLS / "zipalign.exe"
APKSIGNER = BUILD_TOOLS / "apksigner.bat"
KEYTOOL = Path(r"C:\Program Files\Java\jdk-17\bin\keytool.exe")
ICON_DIR = "res/mipmap-anydpi-v26"
ICON = f"{ICON_DIR}/icon.xml"
THEMED = f"{ICON_DIR}/themed_icon.xml"


def editor_settings() -> Path:
    base = Path.home() / "AppData" / "Roaming" / "Godot"
    settings = sorted(base.glob("editor_settings-*.tres"))
    if not settings:
        raise RuntimeError(f"Godot editor settings not found under {base}")
    return settings[-1]


def keystore() -> tuple[Path, str, str]:
    text = editor_settings().read_text(encoding="utf-8", errors="replace")
    path = re.search(r'export/android/debug_keystore\s*=\s*"([^"]+)"', text)
    password = re.search(r'export/android/debug_keystore_pass\s*=\s*"([^"]*)"', text)
    if path is None or password is None:
        raise RuntimeError("debug keystore is not configured in Godot editor settings")
    store = Path(path.group(1))
    if not store.exists():
        raise RuntimeError(f"debug keystore missing: {store}")
    # Godot creates the debug key with this fixed alias and one shared password.
    return store, password.group(1), "androiddebugkey"


def rewrite(source: Path, target: Path) -> None:
    with zipfile.ZipFile(source) as src:
        entries = [(info, src.read(info.filename)) for info in src.infolist()]
    names = {info.filename for info, _ in entries}
    icon = next(data for info, data in entries if info.filename == ICON) if ICON in names else None
    if icon is None:
        raise RuntimeError(f"{ICON} missing from the exported APK")
    with zipfile.ZipFile(target, "w", allowZip64=True) as out:
        for info, data in entries:
            if info.filename.startswith("META-INF/"):
                continue
            copy = zipfile.ZipInfo(info.filename, date_time=info.date_time)
            copy.compress_type = info.compress_type
            copy.external_attr = info.external_attr
            out.writestr(copy, data)
        if THEMED not in names:
            copy = zipfile.ZipInfo(THEMED, date_time=(2026, 1, 1, 0, 0, 0))
            copy.compress_type = zipfile.ZIP_DEFLATED
            out.writestr(copy, icon)


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        output = (proc.stdout or "") + (proc.stderr or "")
        output = re.sub(r"pass:\S+", "pass:<redacted>", output)
        raise RuntimeError(f"command failed ({proc.returncode}):\n{output[-1200:]}")


def main() -> int:
    if not APK.exists():
        print(f"missing APK: {APK}", file=sys.stderr)
        return 1
    java_home = Path(r"C:\Program Files\Java\jdk-17")
    if (java_home / "bin" / "java.exe").exists():
        os.environ["JAVA_HOME"] = str(java_home)
        os.environ["PATH"] = str(java_home / "bin") + os.pathsep + os.environ.get("PATH", "")
    store, password, alias = keystore()
    unsigned = APK.with_name(APK.stem + ".unsigned.apk")
    aligned = APK.with_name(APK.stem + ".aligned.apk")
    signed = APK.with_name(APK.stem + ".signed.apk")
    try:
        rewrite(APK, unsigned)
        run([str(ZIPALIGN), "-f", "4", str(unsigned), str(aligned)])
        run([
            str(APKSIGNER), "sign",
            "--ks", str(store),
            "--ks-pass", f"pass:{password}",
            "--ks-key-alias", alias,
            "--out", str(signed),
            str(aligned),
        ])
        run([str(APKSIGNER), "verify", "--print-certs", str(signed)])
        shutil.move(str(signed), str(APK))
        idsig = Path(str(signed) + ".idsig")
        target_idsig = APK.with_name(APK.name + ".idsig")
        if idsig.exists():
            shutil.move(str(idsig), str(target_idsig))
        elif target_idsig.exists():
            target_idsig.unlink()
        print(f"FIXED {APK} ({THEMED})")
        return 0
    finally:
        for leftover in (unsigned, aligned, signed):
            leftover.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
