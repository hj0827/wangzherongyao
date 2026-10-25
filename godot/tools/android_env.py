#!/usr/bin/env python3
"""Locate the Android SDK / JDK without hardcoding machine-specific paths.

The export tools used to pin ``D:\\AppCache\\Android-Sdk`` and ``jdk-17``; both
moved, and every device run died with ``FileNotFoundError`` before touching the
phone. Resolution order (first hit wins):

1. environment (``ANDROID_HOME`` / ``ANDROID_SDK_ROOT`` / ``JAVA_HOME``)
2. Godot's editor settings -- the same values the exporter itself uses, so the
   scripts can never drift from the APK they are validating
3. a short list of conventional install locations

Self-check: ``python tools/android_env.py`` prints what it resolved and exits
non-zero if any required binary is missing.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

WINDOWS_SDK_CANDIDATES = (
    r"D:\Software\Android\Sdk",
    r"D:\AppCache\Android-Sdk",
    r"C:\Android\Sdk",
)
WINDOWS_JDK_ROOTS = (Path(r"C:\Program Files\Java"), Path(r"C:\Program Files\Eclipse Adoptium"))

BUILD_TOOLS_BINARIES = ("aapt2.exe", "apksigner.bat", "zipalign.exe")


def _version_key(name: str) -> tuple[int, ...]:
    """``36.0.0`` -> ``(36, 0, 0)``; unparsable names sort lowest."""
    parts = re.findall(r"\d+", name)
    return tuple(int(p) for p in parts) if parts else (-1,)


def godot_editor_settings() -> Path | None:
    base = Path.home() / "AppData" / "Roaming" / "Godot"
    found = sorted(base.glob("editor_settings-*.tres"))
    return found[-1] if found else None


def _setting(key: str) -> str | None:
    settings = godot_editor_settings()
    if settings is None:
        return None
    text = settings.read_text(encoding="utf-8", errors="replace")
    hit = re.search(rf'^{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    return hit.group(1) if hit else None


def _existing(paths) -> Path | None:
    for raw in paths:
        if not raw:
            continue
        candidate = Path(raw)
        if candidate.exists():
            return candidate
    return None


def android_sdk() -> Path | None:
    return _existing([
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        _setting("export/android/android_sdk_path"),
        *WINDOWS_SDK_CANDIDATES,
    ])


def build_tools_dir() -> Path | None:
    """Newest build-tools that actually ships the binaries we shell out to."""
    sdk = android_sdk()
    if sdk is None:
        return None
    root = sdk / "build-tools"
    if not root.is_dir():
        return None
    for candidate in sorted(root.iterdir(), key=lambda p: _version_key(p.name), reverse=True):
        if all((candidate / name).exists() for name in BUILD_TOOLS_BINARIES):
            return candidate
    return None


def build_tool(name: str) -> Path | None:
    tools = build_tools_dir()
    if tools is None:
        return None
    binary = tools / name
    return binary if binary.exists() else None


def adb() -> Path | None:
    sdk = android_sdk()
    if sdk is None:
        return None
    binary = sdk / "platform-tools" / "adb.exe"
    return binary if binary.exists() else None


def java_home() -> Path | None:
    env = os.environ.get("JAVA_HOME")
    if env and (Path(env) / "bin" / "java.exe").exists():
        return Path(env)
    configured = _setting("export/android/java_sdk_path")
    if configured and (Path(configured) / "bin" / "java.exe").exists():
        return Path(configured)
    for root in WINDOWS_JDK_ROOTS:
        if not root.is_dir():
            continue
        jdks = sorted(root.glob("jdk*"), key=lambda p: _version_key(p.name), reverse=True)
        for jdk in jdks:
            if (jdk / "bin" / "java.exe").exists():
                return jdk
    return None


def apply_java_home() -> Path | None:
    """Point JAVA_HOME/PATH at the resolved JDK (apksigner needs a JVM)."""
    home = java_home()
    if home is None:
        return None
    os.environ["JAVA_HOME"] = str(home)
    os.environ["PATH"] = str(home / "bin") + os.pathsep + os.environ.get("PATH", "")
    return home


def self_check() -> int:
    sdk = android_sdk()
    tools = build_tools_dir()
    jdk = java_home()
    binary = adb()
    rows = [
        ("android sdk", sdk),
        ("build-tools", tools),
        ("adb", binary),
        ("aapt2", build_tool("aapt2.exe")),
        ("apksigner", build_tool("apksigner.bat")),
        ("zipalign", build_tool("zipalign.exe")),
        ("jdk", jdk),
    ]
    failed = 0
    for label, value in rows:
        if value is None:
            print(f"MISS {label}")
            failed += 1
        else:
            print(f"OK   {label:12} {value}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(self_check())
