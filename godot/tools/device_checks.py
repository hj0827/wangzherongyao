#!/usr/bin/env python3
"""Real-device checks for the Android build (ADB + screenshots, no app changes).

Run from the godot directory:
    python tools/device_checks.py

Every check is recorded; the script keeps going after failures so one run
collects the full device report. Screenshots and report.json are written to
shots/device_checks/<run>/.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import re
import subprocess
import sys
import time
import traceback
import zipfile
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

import android_env

try:
    import numpy as np
except ImportError:  # pragma: no cover - numpy is only used for fast masks
    np = None

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / "shots"
RUN_DIR = SHOTS / "device_checks" / datetime.now().strftime("%Y%m%d_%H%M%S")
REFS = ROOT / "tests" / "device_refs"

# Resolved from env -> Godot editor settings -> conventional install paths, so a
# relocated SDK never shows up as "adb: command not found" mid-run.
DEFAULT_ADB = str(android_env.adb() or "adb")
DEFAULT_AAPT = str(android_env.build_tool("aapt2.exe") or "aapt2")
DEFAULT_APKSIGNER = str(android_env.build_tool("apksigner.bat") or "apksigner")
APK = ROOT / "build" / "android" / "fenghuo-gorge-debug.apk"

PKG = "com.fenghuoxiagu.game"
ACTIVITY = "com.godot.game.GodotAppLauncher"
SERIAL = os.environ.get("ANDROID_SERIAL", "10AC9J0VZA0011K")
ADB = os.environ.get("ADB", DEFAULT_ADB)
AAPT = os.environ.get("AAPT", DEFAULT_AAPT)
APKSIGNER = os.environ.get("APKSIGNER", DEFAULT_APKSIGNER)
android_env.apply_java_home()  # apksigner shells out to java

W, H = 2388, 1080
DENSITY_SCALE = 3.0  # 480dpi / 160

# Virtual layout (1600x900 base, expand => 900px tall, 1990 virtual wide).
VSCALE = H / 900.0
VIRTUAL_W = W / VSCALE


def _vp(vx: float, vy: float) -> tuple[int, int]:
    """Virtual HUD coordinate (top-left origin) -> physical screen coordinate."""
    return (int(round(vx * VSCALE)), int(round(vy * VSCALE)))


def _vrect(x1: float, y1: float, x2: float, y2: float) -> tuple[int, int, int, int]:
    a = _vp(x1, y1)
    b = _vp(x2, y2)
    return (a[0], a[1], b[0], b[1])


MENU_1V1 = (2029, 304)
MENU_5V5 = (2029, 460)
MENU_2P = (2029, 616)
MENU_5P = (2029, 772)
HERO_CONFIRM = (2133, 950)
UI_BACK = (169, 128)
LOBBY_LEAVE = (178, 125)
LOBBY_COPY = (2210, 125)
LOBBY_START = (1194, 758)
ONLINE_CREATE = (633, 935)
JOY_CENTER = (170, 876)
PAUSE_BUTTON = (2285, 403)
PAUSE_RESUME = (1194, 479)
PAUSE_LEAVE = (1194, 644)
ATTACK = _vp(VIRTUAL_W - 18.0 - 76.0, 900.0 - 40.0 - 76.0)

# Mirrors godot/scripts/ui/touch_layout.gd + game_hud.gd. Update both together.
_ATTACK_CENTER = (VIRTUAL_W - 18.0 - 76.0, 900.0 - 40.0 - 76.0)
_ARC_RADIUS = 330.0
_ARC_ANGLES = (185.0, 210.0, 235.0, 260.0)
SKILL_Q, SKILL_W, SKILL_E, SKILL_R = [
    _vp(
        _ATTACK_CENTER[0] + math.cos(math.radians(a)) * _ARC_RADIUS,
        _ATTACK_CENTER[1] + math.sin(math.radians(a)) * _ARC_RADIUS,
    )
    for a in _ARC_ANGLES
]
SUMMONER = _vp(VIRTUAL_W - 736.0, 900.0 - 278.0)
RECALL = _vp(VIRTUAL_W - 544.0, 900.0 - 278.0)
TELEPORT = _vp(VIRTUAL_W - 640.0, 900.0 - 278.0)
SUMMONER_RECT = _vrect(VIRTUAL_W - 784.0, 900.0 - 326.0, VIRTUAL_W - 688.0, 900.0 - 230.0)
RECALL_RECT = _vrect(VIRTUAL_W - 592.0, 900.0 - 326.0, VIRTUAL_W - 496.0, 900.0 - 230.0)
TELEPORT_RECT = _vrect(VIRTUAL_W - 688.0, 900.0 - 326.0, VIRTUAL_W - 592.0, 900.0 - 230.0)
SKILL_RECTS = {
    name: _vrect(
        _ATTACK_CENTER[0] + math.cos(math.radians(a)) * _ARC_RADIUS - 64.0,
        _ATTACK_CENTER[1] + math.sin(math.radians(a)) * _ARC_RADIUS - 74.0,
        _ATTACK_CENTER[0] + math.cos(math.radians(a)) * _ARC_RADIUS + 64.0,
        _ATTACK_CENTER[1] + math.sin(math.radians(a)) * _ARC_RADIUS + 74.0,
    )
    for name, a in zip(("q", "w", "e", "r"), _ARC_ANGLES)
}
SKILL_UNION = (
    min(r[0] for r in SKILL_RECTS.values()),
    min(r[1] for r in SKILL_RECTS.values()),
    max(r[2] for r in SKILL_RECTS.values()),
    max(r[3] for r in SKILL_RECTS.values()),
)
SHOP_BUTTON = _vp(VIRTUAL_W - 95.0, 38.0)
SHOP_PANEL = _vrect(VIRTUAL_W * 0.5 - 390.0, 450.0 - 286.0, VIRTUAL_W * 0.5 + 390.0, 450.0 + 286.0)
SHOP_QUICK_BUY = _vp(VIRTUAL_W * 0.5, 244.0)
SHOP_CLOSE = _vp(VIRTUAL_W * 0.5 + 330.0, 194.0)
MINIMAP_TAP = _vp(135.0, 131.0)
INTEL_PANEL = _vrect(18.0, 294.0, 390.0, 502.0)
INTEL_CLOSE = _vp(352.0, 328.0)
ATTACK_CLUSTER = _vrect(VIRTUAL_W - 500.0, 92.0, VIRTUAL_W - 20.0, 232.0)
ATTACK_MODE_DEFAULT = _vp(VIRTUAL_W - 383.0, 123.0)
ATTACK_MODE_MINION = _vp(VIRTUAL_W - 242.0, 123.0)
ATTACK_MODE_TOWER = _vp(VIRTUAL_W - 101.0, 123.0)
CANCEL_CENTER = _vp(VIRTUAL_W * 0.5, 150.0)
MENU_VIDEO_REGION = (200, 350, 1500, 900)
HERO_VIDEO_REGION = (90, 240, 610, 520)
HERO_VIDEO_REGION_2 = (650, 240, 1170, 520)

# Match menu panel spans 460x460 virtual px at the screen center.
PAUSE_PANEL = (918, 264, 1470, 816)

FIXTURES = ("menu", "hero", "online", "lobby")


class Report:
    def __init__(self) -> None:
        self.rows: list[dict] = []
        self.t0 = time.time()

    def add(self, cid: str, title: str, status: str, detail: str = "") -> None:
        row = {
            "id": cid,
            "title": title,
            "status": status,
            "detail": detail,
            "elapsed_s": round(time.time() - self.t0, 1),
        }
        self.rows.append(row)
        print(f"[{status:5s}] {cid:10s} {title}" + (f" -- {detail}" if detail else ""), flush=True)

    def passed(self, cid: str, title: str, detail: str = "") -> None:
        self.add(cid, title, "PASS", detail)

    def failed(self, cid: str, title: str, detail: str = "") -> None:
        self.add(cid, title, "FAIL", detail)

    def warn(self, cid: str, title: str, detail: str = "") -> None:
        self.add(cid, title, "WARN", detail)

    def skip(self, cid: str, title: str, detail: str = "") -> None:
        self.add(cid, title, "SKIP", detail)

    def info(self, cid: str, title: str, detail: str = "") -> None:
        self.add(cid, title, "INFO", detail)

    def write(self) -> None:
        RUN_DIR.mkdir(parents=True, exist_ok=True)
        payload = {
            "generated": datetime.now().isoformat(timespec="seconds"),
            "serial": SERIAL,
            "package": PKG,
            "results": self.rows,
            "summary": {
                s: sum(1 for r in self.rows if r["status"] == s)
                for s in ("PASS", "FAIL", "WARN", "SKIP", "INFO")
            },
        }
        (RUN_DIR / "report.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


REPORT = Report()
_SHOT_N = 0
_IMG_CACHE: dict[str, Image.Image] = {}


def log(msg: str) -> None:
    print(f"       .. {msg}", flush=True)


def adb(args: list[str], *, binary: bool = False, timeout: int = 30, check: bool = False) -> bytes | str:
    cmd = [ADB, "-s", SERIAL] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        if not restart_adb():
            raise
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
    if proc.returncode != 0 and b"not found" in proc.stderr and restart_adb():
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
    if check and proc.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {proc.stderr.decode('utf-8', 'replace')[:400]}")
    if binary:
        return proc.stdout
    return proc.stdout.decode("utf-8", "replace")


def device_online() -> bool:
    try:
        proc = subprocess.run([ADB, "devices"], capture_output=True, text=True, timeout=15)
    except Exception:
        return False
    return re.search(re.escape(SERIAL) + r"\s+device", proc.stdout) is not None


def restart_adb() -> bool:
    log("adb device lost; restarting adb server")
    try:
        subprocess.run([ADB, "kill-server"], capture_output=True, timeout=20)
    except Exception:
        pass
    time.sleep(0.8)
    try:
        subprocess.run([ADB, "start-server"], capture_output=True, timeout=20)
    except Exception:
        pass
    for _ in range(20):
        if device_online():
            return True
        time.sleep(0.5)
    return False


def ensure_device() -> bool:
    if device_online():
        return True
    return restart_adb()


def sh(command: str, timeout: int = 30) -> str:
    return adb(["shell", command], timeout=timeout)


def foreground_package() -> str:
    try:
        out = sh("dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity'", timeout=15)
    except Exception:
        return ""
    m = re.search(r"(?:topResumedActivity|mResumedActivity)=ActivityRecord\{\S+ u\d+ ([^\s/]+)/", out)
    return m.group(1) if m else ""


def wait_foreground(timeout: float = 10.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if foreground_package() == PKG:
            return True
        time.sleep(0.4)
    return False


def current_focus_package() -> str:
    try:
        out = sh("dumpsys window | grep mCurrentFocus | grep -v null | tail -n1", timeout=15)
    except Exception:
        return ""
    hits = re.findall(r"mCurrentFocus=Window\{\S+ u\d+ ([^\s/]+)/", out)
    return hits[-1] if hits else ""


def wait_focus(timeout: float = 2.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if current_focus_package() == PKG:
            return True
        time.sleep(0.3)
    return False


class ExternalInterference(RuntimeError):
    """Another app (or a system dialog) owns input focus; never send input blindly."""


def ensure_ours(context: str) -> None:
    first = foreground_package()
    if first == PKG and wait_focus(1.2):
        return
    adb(["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}"], timeout=20)
    if wait_foreground(4) and wait_focus(2.0):
        return
    focus = current_focus_package()
    raise ExternalInterference(
        f"{context}: our window does not own focus (top={first or 'unknown'}, focus={focus or 'unknown'})"
    )


def start_app() -> bool:
    adb(["shell", "am", "force-stop", PKG])
    time.sleep(0.5)
    adb(["shell", "am", "start", "-W", "-n", f"{PKG}/{ACTIVITY}"], timeout=30)
    return wait_foreground(12)


def send_back() -> None:
    ensure_ours("sending BACK")
    adb(["shell", "input", "keyevent", "4"])


def press_home() -> None:
    adb(["shell", "input", "keyevent", "3"])


def tap(x: int, y: int) -> None:
    ensure_ours(f"tap {x},{y}")
    adb(["shell", "input", "tap", str(x), str(y)])


def swipe(x1: int, y1: int, x2: int, y2: int, ms: int = 700) -> None:
    ensure_ours(f"swipe {x1},{y1}->{x2},{y2}")
    adb(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms)])


def screenshot(tag: str | None = None, save: bool = False) -> Image.Image:
    global _SHOT_N
    last_error = None
    for attempt in range(5):
        data = adb(["exec-out", "screencap", "-p"], binary=True, timeout=30)
        if len(data) > 10000:
            try:
                img = Image.open(io.BytesIO(data)).convert("RGB")
            except Exception as exc:  # transient truncation
                last_error = exc
                time.sleep(0.6)
                continue
            _SHOT_N += 1
            if save:
                RUN_DIR.mkdir(parents=True, exist_ok=True)
                img.save(RUN_DIR / f"{_SHOT_N:02d}_{tag or 'shot'}.png", optimize=True)
            return img
        last_error = RuntimeError(f"screencap returned {len(data)} bytes")
        time.sleep(0.6)
    try:
        power = sh("dumpsys power | grep -m1 mWakefulness=", timeout=15)
        if "mWakefulness=Awake" not in power:
            adb(["shell", "input", "keyevent", "224"], timeout=15)  # WAKEUP
            time.sleep(1.0)
    except Exception:
        pass
    if restart_adb():
        data = adb(["exec-out", "screencap", "-p"], binary=True, timeout=30)
        if len(data) > 10000:
            try:
                img = Image.open(io.BytesIO(data)).convert("RGB")
                _SHOT_N += 1
                if save:
                    RUN_DIR.mkdir(parents=True, exist_ok=True)
                    img.save(RUN_DIR / f"{_SHOT_N:02d}_{tag or 'shot'}.png", optimize=True)
                return img
            except Exception as exc:
                last_error = exc
    # Some devices intermittently return an empty exec-out stream while SurfaceFlinger is busy.
    for attempt in range(2):
        remote = "/sdcard/fenghuo_check.png"
        try:
            adb(["shell", "screencap", "-p", remote], timeout=30)
            data = adb(["exec-out", "cat", remote], binary=True, timeout=30)
            if len(data) > 10000:
                img = Image.open(io.BytesIO(data)).convert("RGB")
                adb(["shell", "rm", "-f", remote], timeout=15)
                _SHOT_N += 1
                if save:
                    RUN_DIR.mkdir(parents=True, exist_ok=True)
                    img.save(RUN_DIR / f"{_SHOT_N:02d}_{tag or 'shot'}.png", optimize=True)
                return img
        except Exception as exc:
            last_error = exc
        time.sleep(0.8)
    raise RuntimeError(f"screenshot failed: {last_error}")


def fixture(label: str) -> Image.Image:
    if label not in _IMG_CACHE:
        _IMG_CACHE[label] = Image.open(REFS / f"{label}.png").convert("RGB")
    return _IMG_CACHE[label]


def small_gray(img: Image.Image) -> Image.Image:
    return img.convert("L").resize((480, 217), Image.BILINEAR)


def ref_diffs(img: Image.Image) -> dict[str, float]:
    a = np.asarray(small_gray(img), dtype=np.float32)
    out = {}
    for label in FIXTURES:
        b = np.asarray(small_gray(fixture(label)), dtype=np.float32)
        out[label] = float(np.abs(a - b).mean())
    return out


def picture_xy(img: Image.Image) -> tuple[int, int]:
    return img.size


def mean_lum(img: Image.Image, box: tuple[int, int, int, int] | None = None) -> float:
    crop = img.crop(box) if box else img
    return float(ImageStat.Stat(crop.convert("L")).mean[0])


def diff_mean(a: Image.Image, b: Image.Image, box: tuple[int, int, int, int] | None = None) -> float:
    x = a.crop(box) if box else a
    y = b.crop(box) if box else b
    return float(sum(ImageStat.Stat(ImageChops.difference(x, y)).mean) / 3.0)


def np_rgb(img: Image.Image, box: tuple[int, int, int, int] | None = None):
    arr = np.asarray(img.crop(box) if box else img, dtype=np.int16)
    return arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]


def count_mask(img: Image.Image, box: tuple[int, int, int, int], kind: str) -> int:
    r, g, b = np_rgb(img, box)
    if kind == "gold":
        mask = (r > 90) & (r < 235) & (g > 65) & (g < 200) & (b < 120) & ((r - b) > 30) & ((g - b) > 15)
    elif kind == "orange":
        mask = (r > 140) & (g > 65) & (g < 170) & (b < 100) & ((r - b) > 55)
    elif kind == "blue":
        mask = (b > 135) & (g > 90) & (b - r > 25)
    elif kind == "dark":
        mask = (r + g + b) < 210
    elif kind == "bright":
        mask = (r + g + b) > 420
    else:
        raise ValueError(kind)
    return int(mask.sum())


def pause_visible(img: Image.Image) -> bool:
    if mean_lum(img) > 70:
        return False
    x1, y1, x2, y2 = PAUSE_PANEL
    top = count_mask(img, (x1 + 20, y1 - 2, x2 - 20, y1 + 4), "gold")
    bottom = count_mask(img, (x1 + 20, y2 - 4, x2 - 20, y2 + 2), "gold")
    left = count_mask(img, (x1 - 2, y1 + 36, x1 + 6, y2 - 36), "gold")
    right = count_mask(img, (x2 - 6, y1 + 36, x2 + 2, y2 - 36), "gold")
    return top > 250 and bottom > 250 and left > 200 and right > 200


def match_visible(img: Image.Image) -> bool:
    if pause_visible(img) or mean_lum(img) <= 70:
        return False
    atk_dark = count_mask(img, (2190, 850, 2360, 1030), "dark")
    joy_dark = count_mask(img, (30, 730, 310, 1020), "dark")
    return atk_dark > 3000 and joy_dark > 10000


def classify(img: Image.Image) -> str:
    if pause_visible(img):
        return "pause"
    if match_visible(img):
        return "match"
    diffs = ref_diffs(img)
    label = min(diffs, key=diffs.get)
    if diffs[label] <= 9.0:
        return label
    if label == "menu" and diffs["menu"] <= 18.0:
        return "menu"
    sorted_diffs = sorted(diffs.values())
    if sorted_diffs[0] <= 18.0 and (len(sorted_diffs) == 1 or sorted_diffs[1] - sorted_diffs[0] >= 3.0):
        return label
    if mean_lum(img) > 70:
        return "bright"
    return "unknown"


def screen_ok(expected: str, img: Image.Image) -> bool:
    if expected == "match":
        return match_visible(img)
    cls = classify(img)
    if cls == expected:
        return True
    if expected == "menu":
        diffs = ref_diffs(img)
        if min(diffs, key=diffs.get) == "menu" and diffs["menu"] <= 20.0:
            return True
    return False


def wait_screen(expected: str, timeout: float = 6.0, poll: float = 0.7) -> Image.Image:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = screenshot()
        if screen_ok(expected, last):
            return last
        if foreground_package() != PKG:
            adb(["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}"], timeout=20)
            if not wait_foreground(4):
                raise ExternalInterference(f"waiting for {expected}: app lost foreground")
        else:
            focus = current_focus_package()
            if focus and focus != PKG:
                if not wait_focus(1.5):
                    focus = current_focus_package()
                    if focus and focus != PKG:
                        raise ExternalInterference(f"waiting for {expected}: a system window owns focus ({focus})")
        time.sleep(poll)
    return last if last is not None else screenshot()


def expect_screen(cid: str, title: str, expected: str, img: Image.Image, save_tag: str | None = None) -> bool:
    ensure_ours(f"checking {cid}")
    got = classify(img) if expected != "match" else ("match" if screen_ok("match", img) else classify(img))
    ok = screen_ok(expected, img)
    if ok:
        REPORT.passed(cid, title, f"screen={got}")
    else:
        if save_tag:
            RUN_DIR.mkdir(parents=True, exist_ok=True)
            img.save(RUN_DIR / f"FAIL_{save_tag}.png", optimize=True)
        REPORT.failed(cid, title, f"expected {expected}, got {got}, lum={mean_lum(img):.1f}")
    return ok


def minimap_marker(img: Image.Image):
    if np is None:
        return None
    r, g, b = np_rgb(img, (45, 45, 295, 300))
    mask = (r > 150) & (g > 95) & (b < 115) & ((r - b) > 60) & ((g - b) > 25)
    ys, xs = np.nonzero(mask)
    if len(xs) < 8:
        return None
    return (float(xs.mean()) + 45.0, float(ys.mean()) + 45.0, int(len(xs)))


def minimap_blobs(img: Image.Image) -> tuple[int, int]:
    """Count round/square team markers on the minimap (heroes + towers)."""
    if np is None:
        return (0, 0)

    def count(mask: "np.ndarray", min_area: int = 20) -> int:
        seen = np.zeros_like(mask, dtype=bool)
        h, w = mask.shape
        total = 0
        for y0, x0 in zip(*np.nonzero(mask)):
            if seen[y0, x0]:
                continue
            stack = [(int(y0), int(x0))]
            seen[y0, x0] = True
            area = 0
            while stack:
                cy, cx = stack.pop()
                area += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if area >= min_area:
                total += 1
        return total

    r, g, b = np_rgb(img, (45, 45, 295, 300))
    blue = (b > 150) & (g > 90) & ((b - r) > 60) & ((g - r) > 15)
    red = (r > 150) & (g < 110) & (b < 110) & ((r - g) > 60)
    return (count(blue), count(red))


def wait_marker(img: Image.Image):
    m = minimap_marker(img)
    if m is not None:
        return m
    time.sleep(0.3)
    return minimap_marker(screenshot())


def find_rect_border(img: Image.Image, box: tuple[int, int, int, int], kind: str = "gold") -> tuple[int, int]:
    r, g, b = np_rgb(img, box)
    if kind == "gold":
        mask = (r > 90) & (g > 65) & (b < 120) & ((r - b) > 30)
    else:
        mask = (r + g + b) > 300
    rows = mask.sum(axis=1)
    cols = mask.sum(axis=0)
    y = int(rows.argmax()) + box[1]
    x = int(cols.argmax()) + box[0]
    return x, y


def sf_layer_name() -> str:
    try:
        out = sh("dumpsys SurfaceFlinger --list", timeout=20)
    except Exception:
        return ""
    layers = [
        ln.strip()
        for ln in out.splitlines()
        if "SurfaceView[" in ln and PKG in ln and "(BLAST)" in ln and "#" in ln
    ]
    return layers[-1] if layers else ""


def sf_latency(layer: str) -> tuple[int, list[int]]:
    try:
        out = sh(f"dumpsys SurfaceFlinger --latency '{layer}'", timeout=20)
    except Exception:
        return (16666666, [])
    lines = out.strip().splitlines()
    if not lines:
        return (16666666, [])
    try:
        refresh_ns = int(lines[0].strip())
    except ValueError:
        refresh_ns = 16666666
    stamps: set[int] = set()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            actual = int(parts[1])
        except ValueError:
            continue
        if 0 < actual < (1 << 60):
            stamps.add(actual)
    return (refresh_ns, sorted(stamps))


def perf_sample(label: str, duration: float = 6.0, drive: bool = True) -> dict:
    """Sample the Godot SurfaceView present times (gfxinfo only sees Android UI frames)."""
    layer = sf_layer_name()
    if not layer:
        return {"label": label, "error": "Godot SurfaceView layer not found"}
    refresh_ns, seed = sf_latency(layer)
    t0 = seed[-1] if seed else 0
    stamps: set[int] = set()
    end = time.time() + duration
    while time.time() < end:
        if drive:
            swipe(JOY_CENTER[0], JOY_CENTER[1], JOY_CENTER[0] + 120, JOY_CENTER[1], 400)
            tap(SKILL_Q[0], SKILL_Q[1])
        time.sleep(0.35)
        _, rows = sf_latency(layer)
        stamps.update(s for s in rows if s > t0)
    _, rows = sf_latency(layer)
    stamps.update(s for s in rows if s > t0)
    ts = sorted(stamps)
    intervals = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
    if len(ts) < 2 or not intervals:
        return {"label": label, "layer": layer, "error": "no frames captured"}
    ordered = sorted(intervals)
    span_s = (ts[-1] - ts[0]) / 1e9
    refresh_ms = refresh_ns / 1e6
    jank = sum(1 for x in intervals if x > refresh_ms * 1.5)
    return {
        "label": label,
        "layer": layer,
        "frames": len(ts),
        "span_s": span_s,
        "fps": (len(ts) - 1) / span_s if span_s > 0 else 0.0,
        "refresh_ms": refresh_ms,
        "p50": ordered[len(ordered) // 2],
        "p95": ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))],
        "p99": ordered[min(len(ordered) - 1, int(len(ordered) * 0.99))],
        "jank": jank,
        "jank_pct": jank * 100.0 / len(intervals),
        "interval_summary": f"first={intervals[0]:.1f} last={intervals[-1]:.1f} min={min(intervals):.1f} max={max(intervals):.1f}",
    }


def assess_perf(cid: str, data: dict) -> None:
    if data.get("fps") is None:
        REPORT.warn(cid, "frame pacing", data.get("error", "no sample"))
        return
    detail = (
        f"fps={data['fps']:.1f} frames={data['frames']}/{data['span_s']:.1f}s "
        f"p50={data['p50']:.1f}ms p95={data['p95']:.1f}ms jank={data['jank_pct']:.0f}%"
    )
    if data["frames"] < 40:
        REPORT.warn(cid, "frame pacing", "too few frames for a stable sample; " + detail)
        return
    failed = data["fps"] < 25 or data["p95"] > 55
    warned = data["fps"] < 55 or data["p95"] > 33.4 or data["jank_pct"] > 15
    if failed:
        REPORT.failed(cid, "frame pacing", detail)
    elif warned:
        REPORT.warn(cid, "frame pacing", detail)
    else:
        REPORT.passed(cid, "frame pacing", detail)


def sample_live_perf(cid: str, label: str, duration: float) -> dict | None:
    before = screenshot()
    if not match_visible(before):
        REPORT.skip(cid, "frame pacing", f"not a live match before sampling (screen={classify(before)})")
        return None
    data = perf_sample(label, duration=duration)
    after = screenshot()
    if not match_visible(after) or foreground_package() != PKG:
        REPORT.skip(
            cid,
            "frame pacing",
            f"state changed during sampling (screen={classify(after)}, top={foreground_package() or 'unknown'})",
        )
        return data
    assess_perf(cid, data)
    return data


def memory_pss() -> int | None:
    out = sh(f"dumpsys meminfo {PKG}", timeout=30)
    m = re.search(r"TOTAL PSS:\s*(\d+)", out)
    return int(m.group(1)) if m else None


def nav_menu_to_hero(mode_xy: tuple[int, int]) -> bool:
    tap(*mode_xy)
    img = wait_screen("hero", 5.0)
    return screen_ok("hero", img)


def nav_hero_confirm(expected: str, timeout: float = 12.0) -> Image.Image:
    tap(*HERO_CONFIRM)
    return wait_screen(expected, timeout)


def nav_menu_to_online() -> bool:
    if not nav_menu_to_hero(MENU_2P):
        return False
    img = nav_hero_confirm("online")
    return screen_ok("online", img)


def nav_to_lobby() -> bool:
    if not nav_menu_to_online():
        return False
    for attempt in range(2):
        tap(*ONLINE_CREATE)
        img = wait_screen("lobby", 6.0)
        if screen_ok("lobby", img):
            return True
        log(f"create-room tap not registered (attempt {attempt + 1})")
    return False


def ensure_menu() -> bool:
    for attempt in range(2):
        if start_app():
            img = wait_screen("menu", 15.0)
            if screen_ok("menu", img):
                return True
            log(f"menu not detected (attempt {attempt + 1}), screen={classify(img)}")
        time.sleep(1.0)
    return False


def open_pause(attempts: int = 2) -> Image.Image | None:
    for attempt in range(attempts):
        tap(*PAUSE_BUTTON)
        deadline = time.time() + 2.6
        while time.time() < deadline:
            img = screenshot()
            if pause_visible(img):
                return img
            time.sleep(0.4)
        log(f"pause tap not registered (attempt {attempt + 1})")
    return None


def resume_from_pause(attempts: int = 2) -> bool:
    for attempt in range(attempts):
        tap(*PAUSE_RESUME)
        img = wait_screen("match", 4.0)
        if screen_ok("match", img):
            return True
        if not pause_visible(img):
            img = wait_screen("match", 2.0)
            if screen_ok("match", img):
                return True
        log(f"resume tap not registered (attempt {attempt + 1})")
    return False


def leave_match_via_pause(cid: str, title: str) -> bool:
    if open_pause() is None:
        # Check if match result/victory dialog is already showing
        tap(1194, 760)
        img = wait_screen("menu", 6.0)
        if screen_ok("menu", img):
            REPORT.passed(cid, title, "menu after victory dialog return")
            return True
        REPORT.failed(cid, title, "pause overlay did not open")
        return False
    for attempt in range(2):
        tap(*PAUSE_LEAVE)
        img = wait_screen("menu", 6.0)
        if screen_ok("menu", img):
            REPORT.passed(cid, title, "menu after leave")
            return True
        log(f"leave tap not registered (attempt {attempt + 1})")
    REPORT.failed(cid, title, "menu not reached after leave")
    return False


def screen_size_check(img: Image.Image) -> bool:
    return img.size == (W, H)


def back_key_case(cid: str, title: str, expected: str, setup) -> None:
    if not ensure_menu():
        REPORT.skip(cid, title, "could not reach menu")
        return
    if not setup():
        REPORT.skip(cid, title, "could not reach precondition screen")
        return
    before = screenshot()
    if expected == "menu":
        pass
    send_back()
    time.sleep(1.6)
    foreground = foreground_package()
    img = screenshot()
    if foreground != PKG:
        REPORT.failed(
            cid,
            title,
            f"app left foreground after BACK (top={foreground or 'unknown'}); expected {expected}",
        )
        return
    img.save(RUN_DIR / f"back_{cid}.png", optimize=True)
    got = classify(img)
    if screen_ok(expected, img):
        REPORT.passed(cid, title, f"BACK -> {got}")
    else:
        REPORT.failed(cid, title, f"BACK -> {got}, expected {expected}")


def back_pause_resume_case(cid: str, title: str) -> None:
    if not ensure_menu():
        REPORT.skip(cid, title, "could not reach menu")
        return
    if not nav_menu_to_hero(MENU_1V1):
        REPORT.skip(cid, title, "hero select not reached")
        return
    img = nav_hero_confirm("match", 15.0)
    if not screen_ok("match", img):
        REPORT.skip(cid, title, "match not reached")
        return
    if open_pause() is None:
        REPORT.skip(cid, title, "pause overlay not reached")
        return
    send_back()
    time.sleep(1.6)
    top = foreground_package()
    img = screenshot()
    if top != PKG:
        REPORT.failed(cid, title, f"app left foreground after BACK (top={top or 'unknown'})")
    elif match_visible(img):
        REPORT.passed(cid, title, "BACK while paused resumed the match")
    else:
        REPORT.failed(cid, title, f"BACK while paused -> {classify(img)}, expected live match")


def run_static_checks() -> dict:
    info: dict = {}
    devices = adb(["devices"])
    device_ok = re.search(re.escape(SERIAL) + r"\s+device", devices) is not None
    info["device_ok"] = device_ok
    if device_ok:
        REPORT.passed("ENV-01", "ADB device connected", SERIAL)
    else:
        REPORT.failed("ENV-01", "ADB device connected", devices.strip()[-200:])
        log("device offline; continuing with APK/geometry checks only")

    if not APK.exists():
        REPORT.failed("BUILD-01", "APK exists", str(APK))
        return info
    perm_proc = subprocess.run(
        [AAPT, "dump", "permissions", str(APK)], capture_output=True, text=True, timeout=30
    )
    aapt_permissions = perm_proc.stdout + perm_proc.stderr
    badge_proc = subprocess.run(
        [AAPT, "dump", "badging", str(APK)], capture_output=True, text=True, timeout=30
    )
    badging = badge_proc.stdout + badge_proc.stderr
    info["badging"] = badging
    info["permissions"] = aapt_permissions

    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8", errors="replace")
    code = re.search(r"version/code=(\d+)", preset)
    name = re.search(r'version/name="([^"]+)"', preset)
    package = re.search(r'package/unique_name="([^"]+)"', preset)
    installed = sh(f"dumpsys package {PKG}", timeout=20) if device_ok else ""
    inst_name = re.search(r"versionName=([^\s]+)", installed)
    inst_code = re.search(r"versionCode=(\d+)", installed)
    if code and name and package and inst_name and inst_code:
        same = (
            code.group(1) == inst_code.group(1)
            and name.group(1) == inst_name.group(1)
            and package.group(1) == PKG
            and f"versionCode='{code.group(1)}'" in badging
            and f"versionName='{name.group(1)}'" in badging
        )
        detail = f"preset {name.group(1)}/{code.group(1)}, installed {inst_name.group(1)}/{inst_code.group(1)}"
        if same:
            REPORT.passed("BUILD-01", "APK/export/install versions agree", detail)
        else:
            REPORT.failed("BUILD-01", "APK/export/install versions agree", detail)
    elif not device_ok and code and name and f"versionName='{name.group(1)}'" in badging:
        REPORT.warn("BUILD-01", "APK/export/install versions agree", f"device offline; APK matches preset {name.group(1)}/{code.group(1)}")
    else:
        REPORT.warn("BUILD-01", "APK/export/install versions agree", "version fields missing")

    abi = re.search(r"native-code: '([^']+)'", badging)
    min_sdk = re.search(r"minSdkVersion:'(\d+)'", badging)
    if abi and min_sdk:
        abi_ok = abi.group(1) == "arm64-v8a" and int(min_sdk.group(1)) <= 24
        (REPORT.passed if abi_ok else REPORT.failed)(
            "BUILD-02", "ABI / minSdk", f"{abi.group(1)}, minSdk={min_sdk.group(1)}"
        )
    else:
        REPORT.failed("BUILD-02", "ABI / minSdk", "missing native-code/minSdk")

    required = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.CHANGE_WIFI_MULTICAST_STATE",
    ]
    missing = [p for p in required if p not in aapt_permissions]
    if missing:
        REPORT.failed("BUILD-03", "LAN/network permissions", "missing " + ", ".join(missing))
    else:
        REPORT.passed("BUILD-03", "LAN/network permissions", "INTERNET + NETWORK_STATE + MULTICAST")

    try:
        signer = subprocess.run(
            [APKSIGNER, "verify", "--print-certs", str(APK)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        text = (signer.stdout or "") + (signer.stderr or "")
        if signer.returncode == 0 and "Signer #1" in text:
            digest = re.search(r"SHA-256 digest:\s*([0-9a-f]{16})", text)
            REPORT.passed("BUILD-04", "APK signature valid", digest.group(1) if digest else "verified")
        else:
            REPORT.failed("BUILD-04", "APK signature valid", text.strip()[-200:])
    except Exception as exc:
        REPORT.warn("BUILD-04", "APK signature valid", str(exc))

    try:
        with zipfile.ZipFile(APK) as apk_zip:
            names = apk_zip.namelist()
        icon_proc = subprocess.run(
            [AAPT, "dump", "xmltree", str(APK), "--file", "res/mipmap-anydpi-v26/icon.xml"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        icon_tree = icon_proc.stdout
        themed_proc = subprocess.run(
            [AAPT, "dump", "xmltree", str(APK), "--file", "res/mipmap-anydpi-v26/themed_icon.xml"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        themed_tree = themed_proc.stdout
        resource_proc = subprocess.run(
            [AAPT, "dump", "resources", str(APK)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        resource_names = dict(
            re.findall(r"resource (0x7f[0-9a-f]+) (\S+)", resource_proc.stdout)
        )
        layers = [
            layer
            for layer in ("background", "foreground", "monochrome")
            if f"E: {layer} " in icon_tree
        ]
        refs = re.findall(r":drawable\(0x01010199\)=@(0x7f[0-9a-f]+)", icon_tree)
        resolved = [resource_names.get(ref, ref) for ref in refs]
        missing = [
            name
            for name in resolved
            if not any(
                Path(entry).stem.startswith(name.rsplit("/", 1)[-1])
                for entry in names
                if "/mipmap" in entry
            )
        ]
        themed_ok = "E: adaptive-icon" in themed_tree and "E: monochrome " in themed_tree
        if (
            "E: adaptive-icon" in icon_tree
            and len(layers) == 3
            and not missing
            and themed_ok
        ):
            REPORT.passed(
                "BUILD-05",
                "adaptive/themed icon",
                "adaptive icon background/foreground/monochrome + themed_icon.xml packaged",
            )
        else:
            REPORT.failed(
                "BUILD-05",
                "adaptive/themed icon",
                f"layers={layers}, refs={resolved}, missing={missing or 'none'}, "
                f"themed_icon={themed_ok} (run tools/fix_apk_theme_icon.py after export)",
            )
    except Exception as exc:
        REPORT.failed("BUILD-05", "adaptive/themed icon", str(exc))

    try:
        with zipfile.ZipFile(APK) as apk_zip:
            videos = {
                name.rsplit("/", 1)[-1]: apk_zip.getinfo(name).file_size
                for name in apk_zip.namelist()
                if name.endswith(".ogv")
            }
        required_videos = {"menu_bg.ogv", "hero_blade.ogv", "hero_mage.ogv", "hero_tank.ogv", "hero_archer.ogv"}
        missing = sorted(required_videos - set(videos))
        tiny = sorted(name for name in required_videos & set(videos) if videos[name] < 1_000_000)
        if missing or tiny:
            REPORT.failed(
                "BUILD-06",
                "menu/hero videos packaged",
                f"missing={missing}, suspiciously small={tiny}",
            )
        else:
            total = sum(videos[name] for name in required_videos) / (1024 * 1024)
            REPORT.passed("BUILD-06", "menu/hero videos packaged", f"5 ogv files, {total:.1f} MiB")
    except Exception as exc:
        REPORT.failed("BUILD-06", "menu/hero videos packaged", str(exc))

    def overlap(a, b) -> bool:
        return not (a[2] <= b[0] or a[0] >= b[2] or a[3] <= b[1] or a[1] >= b[3])

    utility_rects = {
        "summoner": SUMMONER_RECT,
        "recall": RECALL_RECT,
        "teleport": TELEPORT_RECT,
    }
    clashes = []
    for skill_name, skill_rect in SKILL_RECTS.items():
        for utility_name, utility_rect in utility_rects.items():
            if overlap(skill_rect, utility_rect):
                clashes.append(f"{skill_name.upper()}/{utility_name}")
    if clashes:
        REPORT.failed("UI-01", "skill buttons clear utility buttons", ", ".join(clashes) + " overlap")
    else:
        REPORT.passed("UI-01", "skill buttons clear utility buttons", "no overlap")

    controls = dict(SKILL_RECTS)
    controls.update(utility_rects)
    offscreen = []
    for name, rect in controls.items():
        if rect[0] < 0 or rect[1] < 0 or rect[2] > W or rect[3] > H:
            offscreen.append(name)
    if offscreen:
        REPORT.failed("UI-02", "touch controls stay on screen", ", ".join(offscreen) + " out of bounds")
    else:
        REPORT.passed("UI-02", "touch controls stay on screen", "all inside 2388x1080")

    if not device_ok:
        REPORT.skip("DISP-01", "physical display/density", "device offline")
        info["wifi"] = "unknown"
        return info

    size = sh("wm size")
    density = sh("wm density")
    info["wm_size"] = size.strip()
    info["wm_density"] = density.strip()
    if "1080x2388" in size and "480" in density:
        REPORT.passed("DISP-01", "physical display/density", "1080x2388 @480dpi (3.0x)")
    else:
        REPORT.warn("DISP-01", "physical display/density", f"{size.strip()} {density.strip()}")

    wifi = sh("dumpsys wifi", timeout=30)
    m = re.search(r"Supplicant state:\s*(\w+)", wifi)
    info["wifi"] = m.group(1) if m else "unknown"
    return info


def run_window_checks() -> None:
    if not start_app():
        REPORT.failed("LAUNCH-01", "app launches to foreground", "activity not resumed")
        return
    img = wait_screen("menu", 12.0)
    REPORT.passed("LAUNCH-01", "app launches to foreground", f"top={foreground_package()}")
    expect_screen("LAUNCH-02", "menu renders after cold start", "menu", img, "menu")

    win = sh("dumpsys window windows", timeout=30)
    idx = win.find(f"{PKG}/{ACTIVITY}")
    block = win[idx : win.find("Window #", idx + 10)] if idx >= 0 else ""
    flags_ok = "KEEP_SCREEN_ON" in block
    if flags_ok:
        REPORT.passed("DISP-02", "screen kept awake", "KEEP_SCREEN_ON")
    else:
        REPORT.failed("DISP-02", "screen kept awake", "KEEP_SCREEN_ON flag missing")
    if "Requested visibilities:" in block and "ITYPE_STATUS_BAR: invisible" in block:
        REPORT.passed("DISP-03", "immersive full-screen", "status/navigation bars hidden")
    else:
        REPORT.warn("DISP-03", "immersive full-screen", "bars not reported invisible")
    if "layoutInDisplayCutoutMode=shortEdges" in block:
        REPORT.passed("DISP-04", "draws into cutout edge", "shortEdges")
    else:
        REPORT.warn("DISP-04", "draws into cutout edge", "shortEdges missing")

    displays = sh("dumpsys window displays", timeout=30)
    if "mDisplayRotation=ROTATION_90" in displays and "Requested w=2388 h=1080" in block:
        REPORT.passed("DISP-05", "locked landscape", "ROTATION_90, 2388x1080")
    else:
        REPORT.warn("DISP-05", "locked landscape", "rotation/size not confirmed")
    if screen_size_check(img):
        REPORT.passed("DISP-06", "framebuffer matches window", f"{img.size[0]}x{img.size[1]}")
    else:
        REPORT.failed("DISP-06", "framebuffer matches window", str(img.size))

    left_inset = re.search(r"mAppBounds=Rect\((\d+), 0 - 2388, 1080\)", block)
    if left_inset and int(left_inset.group(1)) > 0:
        REPORT.info(
            "DISP-07",
            "cutout inset reported to app",
            f"mAppBounds starts at x={left_inset.group(1)} but window/UI draws edge-to-edge",
        )


def run_video_checks() -> None:
    """Ogg Theora decoding cannot be exercised headlessly; prove it on the real GPU/decoder."""
    if not ensure_menu():
        REPORT.skip("VIDEO-01", "menu background video plays", "could not reach menu")
        REPORT.skip("VIDEO-02", "hero showcase video plays", "could not reach menu")
        return
    time.sleep(1.6)
    a = screenshot(tag="menu_video_a", save=True)
    time.sleep(2.0)
    b = screenshot(tag="menu_video_b", save=True)
    d = diff_mean(a, b, MENU_VIDEO_REGION)
    if d > 2.0:
        REPORT.passed("VIDEO-01", "menu background video plays", f"2s frame diff={d:.2f}")
    else:
        REPORT.failed("VIDEO-01", "menu background video plays", f"static background (diff={d:.2f})")

    try:
        log_text = adb(["logcat", "-d", "-v", "brief"], timeout=30)
        hit = [ln for ln in log_text.splitlines() if "[background] video:" in ln]
        if hit:
            REPORT.passed("VIDEO-03", "menu video stream loaded", hit[-1].strip()[-120:])
        else:
            REPORT.warn("VIDEO-03", "menu video stream loaded", "no [background] log line; visual check still applies")
    except Exception:
        REPORT.warn("VIDEO-03", "menu video stream loaded", "logcat unavailable")

    if not nav_menu_to_hero(MENU_1V1):
        REPORT.skip("VIDEO-02", "hero showcase video plays", "hero select not reached")
        return
    time.sleep(1.6)
    a = screenshot(tag="hero_video_a", save=True)
    time.sleep(2.0)
    b = screenshot(tag="hero_video_b", save=True)
    d = diff_mean(a, b, HERO_VIDEO_REGION)
    if d > 2.0:
        REPORT.passed("VIDEO-02", "hero showcase video plays", f"selected card diff={d:.2f}")
    else:
        REPORT.failed("VIDEO-02", "hero showcase video plays", f"selected card is static (diff={d:.2f})")

    tap(900, 320)  # second card
    time.sleep(1.5)
    c = screenshot(tag="hero_video2_a", save=True)
    time.sleep(2.0)
    e = screenshot(tag="hero_video2_b", save=True)
    d2 = diff_mean(c, e, HERO_VIDEO_REGION_2)
    if d2 > 2.0:
        REPORT.passed("VIDEO-04", "hero video follows selection", f"second card diff={d2:.2f}")
    else:
        REPORT.warn("VIDEO-04", "hero video follows selection", f"second card static (diff={d2:.2f})")

    tap(300, 320)  # restore the first hero so later match checks stay deterministic
    time.sleep(0.5)
    tap(*UI_BACK)
    wait_screen("menu", 5.0)


def run_hud_feature_checks() -> None:
    """New touch-only HUD surfaces: map intel, shop, attack modes and drag-cast."""
    before = screenshot()
    tap(*MINIMAP_TAP)
    time.sleep(0.8)
    opened = screenshot(tag="map_intel", save=True)
    d = diff_mean(before, opened, INTEL_PANEL)
    if d > 2.0:
        REPORT.passed("INTEL-01", "minimap tap opens map intel", f"panel diff={d:.2f}")
    else:
        REPORT.failed("INTEL-01", "minimap tap opens map intel", f"panel diff={d:.2f}")
    tap(*INTEL_CLOSE)
    time.sleep(0.7)
    closed = screenshot(tag="map_intel_closed", save=True)
    d = diff_mean(opened, closed, INTEL_PANEL)
    if d > 2.0:
        REPORT.passed("INTEL-02", "intel close button dismisses panel", f"panel diff={d:.2f}")
    else:
        REPORT.failed("INTEL-02", "intel close button dismisses panel", f"panel diff={d:.2f}")

    before = screenshot()
    tap(*SHOP_BUTTON)
    time.sleep(0.8)
    opened = screenshot(tag="shop_open", save=True)
    d = diff_mean(before, opened, SHOP_PANEL)
    if d > 3.0:
        REPORT.passed("SHOP-01", "shop button opens equipment panel", f"panel diff={d:.2f}")
    else:
        REPORT.failed("SHOP-01", "shop button opens equipment panel", f"panel diff={d:.2f}")
    tap(*SHOP_QUICK_BUY)
    time.sleep(0.8)
    bought = screenshot(tag="shop_buy", save=True)
    d = diff_mean(opened, bought, SHOP_PANEL)
    if d > 0.2:
        REPORT.passed("SHOP-02", "quick buy changes gold/inventory", f"panel diff={d:.2f}")
    else:
        REPORT.warn("SHOP-02", "quick buy changes gold/inventory", f"no visible change (diff={d:.2f})")
    tap(*SHOP_CLOSE)
    time.sleep(0.7)
    closed = screenshot(tag="shop_closed", save=True)
    d = diff_mean(opened, closed, SHOP_PANEL)
    if d > 3.0:
        REPORT.passed("SHOP-03", "shop close returns to match", f"panel diff={d:.2f}")
    else:
        REPORT.failed("SHOP-03", "shop close returns to match", f"panel diff={d:.2f}")

    for label, point, cid in (
        ("minion", ATTACK_MODE_MINION, "ATK-01"),
        ("tower", ATTACK_MODE_TOWER, "ATK-02"),
        ("default", ATTACK_MODE_DEFAULT, "ATK-03"),
    ):
        before = screenshot()
        tap(*point)
        time.sleep(0.55)
        after = screenshot(tag=f"attack_mode_{label}", save=True)
        d = diff_mean(before, after, ATTACK_CLUSTER)
        if d > 0.2:
            REPORT.passed(cid, f"attack mode {label} responds", f"cluster diff={d:.2f}")
        else:
            REPORT.failed(cid, f"attack mode {label} responds", f"cluster diff={d:.2f}")

    run_skill_cast_checks()


def run_skill_cast_checks() -> None:
    q_rect = SKILL_RECTS["q"]
    aim_point = (SKILL_Q[0] - 300, SKILL_Q[1] - 220)
    aim_region = (500, 200, 2000, 900)

    # World motion alone changes pixels; measure it first so the aim overlay must stand out.
    control_a = screenshot()
    time.sleep(0.8)
    control_b = screenshot()
    baseline = diff_mean(control_a, control_b, aim_region)

    # Cancel first: Q must stay off cooldown, otherwise the cast test is contaminated.
    before = screenshot()
    proc = subprocess.Popen(
        [ADB, "-s", SERIAL, "shell", "input", "swipe", str(SKILL_Q[0]), str(SKILL_Q[1]),
         str(CANCEL_CENTER[0]), str(CANCEL_CENTER[1]), "1800"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(0.7)
    mid = screenshot(tag="cancel_drag", save=True)
    proc.wait(timeout=10)
    time.sleep(0.8)
    after = screenshot(tag="cancel_released", save=True)
    indicator = diff_mean(before, mid, aim_region)
    d_q = diff_mean(before, after, q_rect)
    if indicator > max(0.4, baseline + 0.25):
        REPORT.passed("CAST-01", "drag from Q draws aim indicator", f"aim diff={indicator:.2f} vs world {baseline:.2f}")
    else:
        REPORT.failed("CAST-01", "drag from Q draws aim indicator", f"aim diff={indicator:.2f} vs world {baseline:.2f}")
    if d_q < 1.0:
        REPORT.passed("CAST-02", "drag into cancel zone does not cast", f"Q diff={d_q:.2f}")
    else:
        REPORT.failed("CAST-02", "drag into cancel zone does not cast", f"Q cooldown overlay appeared (diff={d_q:.2f})")

    # Now cast Q by dragging toward the lane.
    before = screenshot()
    proc = subprocess.Popen(
        [ADB, "-s", SERIAL, "shell", "input", "swipe", str(SKILL_Q[0]), str(SKILL_Q[1]),
         str(aim_point[0]), str(aim_point[1]), "1800"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(0.7)
    mid = screenshot(tag="cast_drag", save=True)
    proc.wait(timeout=10)
    time.sleep(0.9)
    after = screenshot(tag="cast_released", save=True)
    indicator = diff_mean(before, mid, aim_region)
    d_q = diff_mean(before, after, q_rect)
    if indicator > max(0.4, baseline + 0.25):
        REPORT.passed("CAST-03", "drag-cast shows aim preview", f"aim diff={indicator:.2f} vs world {baseline:.2f}")
    else:
        REPORT.failed("CAST-03", "drag-cast shows aim preview", f"aim diff={indicator:.2f} vs world {baseline:.2f}")
    if d_q > 1.0:
        REPORT.passed("CAST-04", "releasing drag casts Q", f"Q cooldown diff={d_q:.2f}")
    else:
        tap(*SKILL_Q)
        time.sleep(0.5)
        after_tap = screenshot(tag="cast_fallback_tap", save=True)
        d_tap = diff_mean(before, after_tap, q_rect)
        if d_tap > 1.0:
            REPORT.warn("CAST-04", "drag-cast release / tap cast", f"swipe release diff={d_q:.2f}, tap cast confirmed diff={d_tap:.2f}")
        else:
            REPORT.failed("CAST-04", "releasing drag casts Q", f"no cooldown overlay (diff={d_q:.2f})")

    time.sleep(7.0)  # longest hero Q cooldown is 6s; keep the later tap-based SKILL-01 honest
    before = screenshot()
    tap(*SUMMONER)
    time.sleep(0.8)
    after = screenshot(tag="summoner", save=True)
    d = diff_mean(before, after, SUMMONER_RECT)
    if d > 1.0:
        REPORT.passed("CAST-05", "summoner flash responds", f"button diff={d:.2f}")
    else:
        REPORT.failed("CAST-05", "summoner flash responds", f"button diff={d:.2f}")

    time.sleep(1.0)
    before = screenshot()
    tap(*RECALL)
    time.sleep(0.8)
    after = screenshot(tag="recall", save=True)
    d_recall = diff_mean(before, after, RECALL_RECT)
    if d_recall > 0.5:
        REPORT.passed("CAST-06", "recall button responds", f"button diff={d_recall:.2f}")
    else:
        REPORT.failed("CAST-06", "recall button responds", f"button diff={d_recall:.2f}")

    time.sleep(1.0)
    before = screenshot()
    tap(*TELEPORT)
    time.sleep(0.8)
    after = screenshot(tag="teleport", save=True)
    d_tp = diff_mean(before, after, TELEPORT_RECT)
    if d_tp > 0.5:
        REPORT.passed("CAST-07", "teleport button responds", f"button diff={d_tp:.2f}")
    else:
        REPORT.failed("CAST-07", "teleport button responds", f"button diff={d_tp:.2f}")


def run_navigation_checks() -> None:
    if not ensure_menu():
        REPORT.failed("NAV-00", "reach menu for navigation", "failed")
        return

    if not nav_menu_to_hero(MENU_1V1):
        REPORT.failed("NAV-01", "menu -> 1v1 hero select", "hero screen not detected")
        return
    REPORT.passed("NAV-01", "menu -> 1v1 hero select", f"cards_ref_diff={ref_diffs(screenshot())}")
    before = screenshot(tag="hero_before_pick", save=True)
    tap(900, 320)
    time.sleep(0.9)
    after = screenshot(tag="hero_after_pick", save=True)
    d = diff_mean(before, after, (0, 150, 2388, 610))
    if d > 0.5:
        REPORT.passed("NAV-02", "hero card selection changes", f"diff={d:.2f}")
    else:
        REPORT.failed("NAV-02", "hero card selection changes", f"diff={d:.2f}")

    tap(*UI_BACK)
    img = wait_screen("menu", 5.0)
    expect_screen("NAV-03", "hero UI back -> menu", "menu", img, "nav_hero_back")

    if not nav_menu_to_online():
        REPORT.failed("NAV-04", "menu -> 2P online screen", "online screen not detected")
        return
    online = screenshot(tag="online_2p", save=True)
    expect_screen("NAV-04", "menu -> 2P online screen", "online", online, "nav_online")

    tap(*UI_BACK)
    img = wait_screen("hero", 5.0)
    expect_screen("NAV-05", "online UI back -> hero select", "hero", img, "nav_online_back")
    tap(*UI_BACK)
    img = wait_screen("menu", 5.0)
    expect_screen("NAV-06", "hero UI back -> menu", "menu", img, "nav_hero_back2")

    if not nav_menu_to_online():
        REPORT.failed("NAV-07", "create room -> lobby", "could not reach online screen")
        return
    created = False
    for attempt in range(2):
        tap(*ONLINE_CREATE)
        img = wait_screen("lobby", 6.0)
        if screen_ok("lobby", img):
            created = True
            break
        log(f"create-room tap was not registered (attempt {attempt + 1})")
    if created:
        REPORT.passed("NAV-07", "create room -> lobby", "lobby detected")
        lobby = screenshot(tag="lobby", save=True)
        before = screenshot()
        tap(*LOBBY_COPY)
        time.sleep(0.8)
        after = screenshot(tag="lobby_copy", save=True)
        d = diff_mean(before, after, (980, 890, 1420, 965))
        if d > 0.12:
            REPORT.passed("NAV-08", "copy room code feedback", f"status diff={d:.2f}")
        else:
            REPORT.warn("NAV-08", "copy room code feedback", f"no visible status change (diff={d:.2f})")
        tap(*LOBBY_LEAVE)
        img = wait_screen("online", 6.0)
        expect_screen("NAV-09", "lobby UI leave -> online", "online", img, "nav_lobby_leave")
    else:
        REPORT.failed("NAV-07", "create room -> lobby", "lobby not detected after 2 taps")


def run_back_checks() -> None:
    def setup_hero() -> bool:
        return nav_menu_to_hero(MENU_1V1)

    def setup_online() -> bool:
        return nav_menu_to_online()

    def setup_lobby() -> bool:
        return nav_to_lobby()

    def setup_match() -> bool:
        if not nav_menu_to_hero(MENU_1V1):
            return False
        img = nav_hero_confirm("match", 15.0)
        return screen_ok("match", img)

    back_key_case("BACK-01", "hardware BACK from hero select -> menu", "menu", setup_hero)
    back_key_case("BACK-02", "hardware BACK from online -> menu", "menu", setup_online)
    back_key_case("BACK-03", "hardware BACK from lobby -> online", "online", setup_lobby)
    back_key_case("BACK-04", "hardware BACK in match -> pause overlay", "pause", setup_match)
    back_pause_resume_case("BACK-05", "hardware BACK while paused -> resume match")


def verify_hud(img: Image.Image, prefix: str = "HUD") -> None:
    r, g, b = np_rgb(img, (18, 40, 28, 300))
    gold_col = (r > 90) & (g > 65) & (b < 120) & ((r - b) > 30)
    col_counts = gold_col.sum(axis=0)
    best_x = int(col_counts.argmax()) + 18 if len(col_counts) else -1
    best_col = int(col_counts.max()) if len(col_counts) else 0
    interior_lum = mean_lum(img, (30, 30, 290, 310))
    outside_lum = mean_lum(img, (340, 30, 640, 310))
    if 10 <= best_x <= 80 and best_col > 150 and interior_lum < 80 and outside_lum > interior_lum + 20:
        REPORT.passed(f"{prefix}-01", "minimap anchored top-left", f"border_x={best_x}, lum {interior_lum:.0f} vs {outside_lum:.0f}")
    else:
        REPORT.failed(
            f"{prefix}-01",
            "minimap anchored top-left",
            f"border_x={best_x}, col_px={best_col}, lum {interior_lum:.0f} vs {outside_lum:.0f}",
        )

    joy_dark = count_mask(img, (30, 730, 310, 1020), "dark")
    joy_area = (310 - 30) * (1020 - 730)
    joy_gold = count_mask(img, (30, 730, 310, 1020), "gold")
    if joy_dark / joy_area > 0.30 and joy_gold > 80:
        REPORT.passed(f"{prefix}-02", "joystick bottom-left", f"dark={joy_dark/joy_area:.0%} gold_px={joy_gold}")
    else:
        REPORT.failed(f"{prefix}-02", "joystick bottom-left", f"dark={joy_dark/joy_area:.0%} gold_px={joy_gold}")

    atk_dark = count_mask(img, (2190, 850, 2360, 1030), "dark")
    atk_area = (2360 - 2190) * (1030 - 850)
    atk_orange = count_mask(img, (2190, 850, 2360, 1030), "orange")
    if atk_dark / atk_area > 0.25 and atk_orange > 60:
        REPORT.passed(f"{prefix}-03", "attack button bottom-right", f"dark={atk_dark/atk_area:.0%} orange_px={atk_orange}")
    else:
        REPORT.failed(f"{prefix}-03", "attack button bottom-right", f"dark={atk_dark/atk_area:.0%} orange_px={atk_orange}")

    q_gold = count_mask(img, SKILL_RECTS["q"], "gold")
    e_blue = count_mask(img, SKILL_RECTS["e"], "blue")
    if q_gold > 100 and e_blue > 100:
        REPORT.passed(f"{prefix}-04", "Q/E skills arc around attack", f"q_gold={q_gold} e_blue={e_blue}")
    else:
        REPORT.failed(f"{prefix}-04", "Q/E skills arc around attack", f"q_gold={q_gold} e_blue={e_blue}")

    pause_dark = count_mask(img, (2210, 330, 2360, 478), "dark")
    pause_bright = count_mask(img, (2210, 330, 2360, 478), "bright")
    if pause_dark > 1200 and pause_bright > 60:
        REPORT.passed(f"{prefix}-05", "pause button top-right", f"dark={pause_dark} bright={pause_bright}")
    else:
        REPORT.failed(f"{prefix}-05", "pause button top-right", f"dark={pause_dark} bright={pause_bright}")

    score_dark = count_mask(img, (900, 15, 1480, 110), "dark")
    hero_dark = count_mask(img, (690, 860, 1740, 1035), "dark")
    if score_dark > 10000 and hero_dark > 50000:
        REPORT.passed(f"{prefix}-06", "score bar and hero panel", f"score={score_dark} panel={hero_dark}")
    else:
        REPORT.failed(f"{prefix}-06", "score bar and hero panel", f"score={score_dark} panel={hero_dark}")

    # virtual sizes converted to physical px, then /3 for dp (480dpi screen)
    def vdp(v: float) -> float:
        return v * VSCALE / DENSITY_SCALE

    sizes = {
        "pause": (vdp(120), vdp(120)),
        "skills": (vdp(128), vdp(148)),
        "pause-menu buttons": (vdp(432), vdp(120)),
        "result button": (vdp(632), vdp(120)),
        "menu buttons": (vdp(358), vdp(120)),
    }
    small = [f"{name} {w:.1f}x{h:.1f}dp" for name, (w, h) in sizes.items() if w < 47.9 or h < 47.9]
    detail = "; ".join(f"{name} {w:.1f}x{h:.1f}dp" for name, (w, h) in sizes.items())
    if small:
        REPORT.failed(f"{prefix}-07", "touch targets below 48dp", ", ".join(small) + f" ({detail})")
    else:
        REPORT.passed(f"{prefix}-07", "touch targets >= 48dp", detail)


def run_safe_area_checks() -> None:
    displays = sh("dumpsys window displays", timeout=30)
    cut = None
    corners = []
    for section in displays.split("mDisplayCutout=DisplayCutout{")[1:]:
        m = re.search(r"Bounds=\[Rect\((\d+), (\d+) - (\d+), (\d+)\)", section)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 > x1 and y2 > y1:
            cut = (x1, y1, x2, y2)
            cm = re.search(r"mRoundedCorners=RoundedCorners\{\[([^\]]+)\]", section)
            if cm:
                corners = [
                    (int(r), int(x), int(y))
                    for r, x, y in re.findall(r"radius=(\d+), center=Point\((\d+), (\d+)\)", cm.group(1))
                ]
            break
    if not cut:
        # older dump format fallback
        m = re.search(r"mDisplayCutout=DisplayCutout\{insets=Rect\(([-\d]+), ([-\d]+) - ([-\d]+), ([-\d]+)\)", displays)
        cut = tuple(map(int, m.groups())) if m and any(int(v) for v in m.groups()) else None
    if cut:
        controls = {
            "minimap": (22, 22, 312, 310),
            "joystick": (14, 720, 326, 1032),
            "attack": (2184, 850, 2366, 1032),
            "pause": (2210, 330, 2360, 478),
            "skills": SKILL_UNION,
        }
        overlaps = []
        for name, rect in controls.items():
            if not (rect[2] <= cut[0] or rect[0] >= cut[2] or rect[3] <= cut[1] or rect[1] >= cut[3]):
                overlaps.append(name)
        if overlaps:
            REPORT.failed("SAFE-01", "controls avoid display cutout", f"cutout={cut}; overlaps {overlaps}")
        else:
            REPORT.passed("SAFE-01", "controls avoid display cutout", f"cutout={cut}")

        def clipped(pt: tuple[int, int]) -> bool:
            x, y = pt
            for radius, cx, cy in corners:
                if radius <= 0:
                    continue
                sx = 1 if cx < W / 2 else -1
                sy = 1 if cy < H / 2 else -1
                dx = (x - cx) * sx
                dy = (y - cy) * sy
                # only the r*r square between the corner and the arc center is clipped
                if 0 <= dx <= radius and 0 <= dy <= radius and dx * dx + dy * dy > radius * radius:
                    return True
            return False

        hit = []
        for name, rect in controls.items():
            pts = [(rect[0], rect[1]), (rect[2], rect[1]), (rect[2], rect[3]), (rect[0], rect[3])]
            if any(clipped(p) for p in pts):
                hit.append(name)
        if hit:
            REPORT.warn("SAFE-02", "rounded-corner clipping", f"corner radius=88; clipped corners: {hit} (cosmetic)")
        else:
            REPORT.passed("SAFE-02", "rounded-corner clipping", "no control corner clipped")
    else:
        REPORT.skip("SAFE-01", "controls avoid display cutout", "cutout not reported")
        REPORT.skip("SAFE-02", "rounded-corner clipping", "rounded corners not reported")


def run_match_and_input_checks() -> None:
    if not ensure_menu():
        REPORT.failed("MATCH-01", "enter 1v1 match", "could not reach menu")
        return
    if not nav_menu_to_hero(MENU_1V1):
        REPORT.failed("MATCH-01", "enter 1v1 match", "hero select not reached")
        return
    img = nav_hero_confirm("match", 15.0)
    if not expect_screen("MATCH-01", "enter 1v1 match", "match", img, "match_1v1"):
        return
    match = screenshot(tag="match_1v1_ready", save=True)

    verify_hud(match)
    run_safe_area_checks()

    # Minimap marker counts also prove which mode actually launched.
    blue, red = minimap_blobs(match)
    if blue <= 14 and red <= 10 and (blue + red) < 25:
        REPORT.passed("MODE1-01", "1v1 minimap shows two heroes", f"blue={blue} red={red} markers")
    else:
        REPORT.failed("MODE1-01", "1v1 minimap shows two heroes", f"blue={blue} red={red} markers (5v5?)")

    def skip_rest(reason: str, include_pause04: bool = True) -> None:
        if include_pause04:
            REPORT.skip("PAUSE-04", "simulation resumes after unpause", reason)
        REPORT.skip("LIFE-01", "HOME then resume keeps match", reason)
        for move in ("UP", "DOWN", "RIGHT", "LEFT"):
            REPORT.skip(f"MOVE-{move}", f"joystick {move.lower()} direction", reason)
        REPORT.skip("MOVE-05", "four directions are orthogonal and opposite", reason)
        REPORT.skip("MOVE-06", "releasing joystick stops movement", reason)
        REPORT.skip("PERF-01", "frame pacing", reason)

    # 1) Pause overlay must freeze the simulation completely. Run right away while safe at spawn.
    paused = open_pause()
    if paused is None:
        REPORT.failed("PAUSE-01", "pause button shows overlay", "overlay not detected after 2 taps")
        REPORT.skip("PAUSE-02", "pause freezes simulation", "pause overlay unavailable")
        REPORT.skip("PAUSE-03", "resume returns to match", "pause overlay unavailable")
        skip_rest("pause overlay unavailable")
        return
    REPORT.passed("PAUSE-01", "pause button shows overlay", f"lum={mean_lum(paused):.1f}")
    frozen = screenshot(tag="pause_freeze_a", save=True)
    time.sleep(1.2)
    frozen2 = screenshot(tag="pause_freeze_b", save=True)
    if not pause_visible(frozen) or not pause_visible(frozen2):
        REPORT.warn("PAUSE-02", "pause freezes simulation", "overlay vanished between frames")
    else:
        dp = diff_mean(frozen, frozen2, (0, 120, 2388, 1000))
        if dp < 0.05:
            REPORT.passed("PAUSE-02", "pause freezes simulation", f"frame_diff={dp:.4f}")
        else:
            REPORT.failed("PAUSE-02", "pause freezes simulation", f"frame_diff={dp:.4f}")

    if not resume_from_pause():
        still = screenshot(tag="resume_failed", save=True)
        REPORT.failed("PAUSE-03", "resume returns to match", f"screen={classify(still)} after 2 taps")
        skip_rest("resume failed")
        if pause_visible(screenshot()):
            tap(*PAUSE_LEAVE)
            wait_screen("menu", 6.0)
        return
    REPORT.passed("PAUSE-03", "resume returns to match", "overlay gone")
    a = screenshot()
    time.sleep(0.9)
    b = screenshot()
    live = diff_mean(a, b, (0, 120, 2388, 1000))
    if not match_visible(b):
        REPORT.failed("PAUSE-04", "simulation resumes after unpause", f"screen={classify(b)}")
    elif live > 0.03:
        REPORT.passed("PAUSE-04", "simulation resumes after unpause", f"frame_diff={live:.3f}")
    else:
        REPORT.warn("PAUSE-04", "simulation resumes after unpause", f"frame_diff={live:.3f}")

    # 2) HOME / resume lifecycle.
    press_home()
    time.sleep(1.8)
    home_top = foreground_package()
    adb(["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}"], timeout=20)
    resumed_ok = wait_foreground(8)
    time.sleep(2.0)
    back_img = screenshot(tag="after_home", save=True)
    if pause_visible(back_img):
        resumed_ok = resume_from_pause() and resumed_ok
        back_img = screenshot()
    if home_top != PKG and resumed_ok and match_visible(back_img):
        REPORT.passed("LIFE-01", "HOME then resume keeps match", f"home_top={home_top}")
    else:
        REPORT.failed(
            "LIFE-01",
            "HOME then resume keeps match",
            f"home_top={home_top}, screen={classify(back_img)}",
        )
        skip_rest("match not live after HOME", include_pause04=False)
        return

    # 3) Movement immediately after lifecycle checks.
    moves: dict[str, tuple[float, float]] = {}
    direction_data = {
        "up": (0, -130),
        "down": (0, 130),
        "right": (130, 0),
        "left": (-130, 0),
    }
    for name, (dx, dy) in direction_data.items():
        before = screenshot()
        if not match_visible(before):
            for rest in list(direction_data)[list(direction_data).index(name):]:
                REPORT.skip(f"MOVE-{rest.upper()}", f"joystick {rest} direction", "match no longer live")
            break
        m0 = wait_marker(before)
        if m0 is None:
            REPORT.failed(f"MOVE-{name.upper()}", f"joystick {name} direction", "minimap marker not found")
            continue
        swipe(JOY_CENTER[0], JOY_CENTER[1], JOY_CENTER[0] + dx, JOY_CENTER[1] + dy, 1200)
        time.sleep(0.8)
        after = screenshot(tag=f"move_{name}", save=True)
        m1 = minimap_marker(after)
        if m1 is None:
            REPORT.failed(f"MOVE-{name.upper()}", f"joystick {name} direction", "marker lost after move")
            continue
        delta = (m1[0] - m0[0], m1[1] - m0[1])
        moves[name] = delta
        mag = math.hypot(*delta)
        expected = {
            "up": (delta[0] > 0.4 and delta[1] > 0.4),
            "down": (delta[0] < -0.4),
            "right": (delta[0] < -0.4 and delta[1] > 0.4),
            "left": (delta[0] > 0.4 and delta[1] < -0.4),
        }[name]
        if expected and mag >= 1.5:
            REPORT.passed(f"MOVE-{name.upper()}", f"joystick {name} direction", f"minimap_delta=({delta[0]:.1f},{delta[1]:.1f})")
        else:
            REPORT.failed(f"MOVE-{name.upper()}", f"joystick {name} direction", f"minimap_delta=({delta[0]:.1f},{delta[1]:.1f})")

    if all(k in moves for k in ("up", "down", "left", "right")):
        def v(name):
            return moves[name]

        def cos(a, b):
            na = math.hypot(*a)
            nb = math.hypot(*b)
            return (a[0] * b[0] + a[1] * b[1]) / (na * nb) if na > 0 and nb > 0 else 0.0

        upright = cos(v("up"), v("right"))
        updown = cos(v("up"), v("down"))
        leftright = cos(v("left"), v("right"))
        if abs(upright) < 0.55 and updown < -0.5 and leftright < -0.5:
            REPORT.passed(
                "MOVE-05",
                "four directions are orthogonal and opposite",
                f"cos(up,right)={upright:.2f} cos(up,down)={updown:.2f} cos(left,right)={leftright:.2f}",
            )
        else:
            REPORT.failed(
                "MOVE-05",
                "four directions are orthogonal and opposite",
                f"cos(up,right)={upright:.2f} cos(up,down)={updown:.2f} cos(left,right)={leftright:.2f}",
            )
    else:
        REPORT.skip("MOVE-05", "four directions are orthogonal and opposite", "missing direction samples")

    stop_a = screenshot()
    ma = minimap_marker(stop_a)
    time.sleep(1.2)
    stop_b = screenshot()
    mb = minimap_marker(stop_b)
    if ma and mb:
        drift = math.hypot(mb[0] - ma[0], mb[1] - ma[1])
        if drift < 1.0:
            REPORT.passed("MOVE-06", "releasing joystick stops movement", f"drift={drift:.2f}px")
        else:
            REPORT.failed("MOVE-06", "releasing joystick stops movement", f"drift={drift:.2f}px")
    else:
        REPORT.warn("MOVE-06", "releasing joystick stops movement", "marker unavailable")

    # 4) HUD Features (minimap intel, shop, attack modes, drag cast)
    run_hud_feature_checks()

    # 5) Skills tap execution & hold attack
    before = screenshot()
    tap(*SKILL_Q)
    time.sleep(0.35)
    after = screenshot(tag="skill_q", save=True)
    dq = diff_mean(before, after, SKILL_RECTS["q"])
    if dq > 1.0:
        REPORT.passed("SKILL-01", "Q skill responds", f"hud_diff={dq:.2f}")
    else:
        REPORT.failed("SKILL-01", "Q skill responds", f"hud_diff={dq:.2f}")

    time.sleep(3.2)
    before = screenshot()
    tap(*SKILL_E)
    time.sleep(0.35)
    after = screenshot(tag="skill_e", save=True)
    de = diff_mean(before, after, SKILL_RECTS["e"])
    if de > 2.0:
        REPORT.passed("SKILL-02", "E skill responds", f"hud_diff={de:.2f}")
    else:
        REPORT.failed("SKILL-02", "E skill responds", f"hud_diff={de:.2f}")

    time.sleep(3.2)
    before = screenshot()
    tap(*SKILL_W)
    time.sleep(0.35)
    after = screenshot(tag="skill_w", save=True)
    dw = diff_mean(before, after, SKILL_RECTS["w"])
    if dw > 1.0:
        REPORT.passed("SKILL-W", "W skill responds", f"hud_diff={dw:.2f}")
    else:
        REPORT.failed("SKILL-W", "W skill responds", f"hud_diff={dw:.2f}")

    time.sleep(3.2)
    before = screenshot()
    tap(*SKILL_R)
    time.sleep(0.35)
    after = screenshot(tag="skill_r", save=True)
    dr = diff_mean(before, after, SKILL_RECTS["r"])
    if dr > 1.0:
        REPORT.passed("SKILL-R", "R skill responds", f"hud_diff={dr:.2f}")
    else:
        REPORT.failed("SKILL-R", "R skill responds", f"hud_diff={dr:.2f}")

    before = screenshot()
    holder = subprocess.Popen(
        [ADB, "-s", SERIAL, "shell", "input", "swipe", str(ATTACK[0]), str(ATTACK[1]),
         str(ATTACK[0]), str(ATTACK[1]), "1400"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.55)
    during = screenshot(tag="attack_hold", save=True)
    holder.wait(timeout=10)
    time.sleep(0.3)
    da = diff_mean(before, during, (2190, 850, 2360, 1030))
    if da > 0.8:
        REPORT.passed("SKILL-03", "hold attack responds", f"hud_diff={da:.2f}")
    else:
        REPORT.failed("SKILL-03", "hold attack responds", f"hud_diff={da:.2f}")

    data = sample_live_perf("PERF-01", "1v1", duration=6.0)
    if data:
        RUN_DIR.mkdir(parents=True, exist_ok=True)
        (RUN_DIR / "sf_1v1.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    pss = memory_pss()
    if pss:
        level = "WARN" if pss > 600_000 else "PASS"
        REPORT.add("PERF-03", "memory footprint", level, f"PSS={pss/1024:.0f} MiB")
    else:
        REPORT.warn("PERF-03", "memory footprint", "unavailable")

    leave_match_via_pause("PAUSE-05", "leave match returns to menu")


def run_5v5_checks() -> None:
    if not ensure_menu():
        REPORT.failed("MODE5-01", "enter 5v5 AI match", "could not reach menu")
        return
    if not nav_menu_to_hero(MENU_5V5):
        REPORT.failed("MODE5-01", "enter 5v5 AI match", "hero select not reached")
        return
    tap(2030, 320)  # fourth hero card
    time.sleep(0.5)
    img = nav_hero_confirm("match", 18.0)
    if not expect_screen("MODE5-01", "enter 5v5 AI match", "match", img, "match_5v5"):
        return
    shot = screenshot(tag="match_5v5_ready", save=True)
    verify_hud(shot, "HUD5")
    blue, red = minimap_blobs(shot)
    if blue >= 10 and red >= 10:
        REPORT.passed("MODE5-00", "5v5 minimap shows ten heroes", f"blue={blue} red={red} markers")
    else:
        REPORT.failed(
            "MODE5-00",
            "5v5 minimap shows ten heroes",
            f"blue={blue} red={red} markers; expected 10v10 markers (1v1 has ~5 per side)",
        )
    data = sample_live_perf("PERF-02", "5v5", duration=8.0)
    if data:
        (RUN_DIR / "sf_5v5.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    leave_match_via_pause("MODE5-02", "leave 5v5 AI match -> menu")


def start_online_match() -> bool:
    if not ensure_menu():
        return False
    if not nav_to_lobby():
        return False
    tap(*LOBBY_START)
    img = wait_screen("match", 15.0)
    return screen_ok("match", img)


def run_online_host_checks(wifi_state: str) -> None:
    if not ensure_menu():
        REPORT.failed("ONLINE-01", "host online match", "could not reach menu")
        return
    if not nav_to_lobby():
        REPORT.failed("ONLINE-01", "host online match", "lobby not reached")
        return
    lobby = screenshot(tag="online_lobby", save=True)
    REPORT.passed("ONLINE-01", "host room reaches lobby", f"lobby detection={classify(lobby)}")

    tap(*LOBBY_START)
    img = wait_screen("match", 15.0)
    if not expect_screen("ONLINE-02", "host starts online match", "match", img, "online_match"):
        return
    screenshot(tag="online_match_ready", save=True)

    # BACK opens the match menu without pausing; a second BACK returns to the live match.
    live = True
    send_back()
    time.sleep(1.0)
    top = foreground_package()
    opened = screenshot(tag="online_back_menu", save=True) if top == PKG else None
    if top != PKG:
        REPORT.failed("ONLINE-05", "BACK toggles the online match menu without exiting", f"app left foreground (top={top})")
        live = False
    elif not pause_visible(opened):
        REPORT.failed("ONLINE-05", "BACK toggles the online match menu without exiting", f"BACK did not open the menu (screen={classify(opened)})")
    else:
        send_back()
        time.sleep(1.1)
        top2 = foreground_package()
        closed = screenshot(tag="online_back_closed", save=True) if top2 == PKG else None
        if top2 == PKG and closed is not None and match_visible(closed):
            REPORT.passed("ONLINE-05", "BACK toggles the online match menu without exiting", "menu opened, second BACK resumed")
        else:
            REPORT.failed("ONLINE-05", "BACK toggles the online match menu without exiting", f"second BACK did not return to the live match (top={top2})")
            live = bool(closed is not None and match_visible(closed))

    if not live:
        live = start_online_match()
        if not live:
            REPORT.skip("ONLINE-03", "online menu keeps the simulation running", "online match not reachable")

    if live:
        swipe(JOY_CENTER[0], JOY_CENTER[1], JOY_CENTER[0] + 100, JOY_CENTER[1], 400)
        time.sleep(0.3)
        menu = open_pause()
        if menu is None:
            REPORT.failed("ONLINE-03", "online menu keeps the simulation running", "match menu did not open")
        else:
            a = screenshot(tag="online_menu_a", save=True)
            time.sleep(1.2)
            b = screenshot(tag="online_menu_b", save=True)
            moved = diff_mean(a, b, (0, 120, 2388, 1000))
            moved_map = diff_mean(a, b, (45, 45, 295, 300))
            if not pause_visible(b):
                REPORT.failed("ONLINE-03", "online menu keeps the simulation running", "match menu vanished between frames")
            elif moved > 0.015 or moved_map > 0.005:
                REPORT.passed("ONLINE-03", "online menu keeps the simulation running", f"frame_diff={moved:.3f}, map_diff={moved_map:.3f}")
            else:
                REPORT.failed("ONLINE-03", "online menu keeps the simulation running", f"simulation appears frozen (frame_diff={moved:.3f})")
            tap(*PAUSE_RESUME)
            time.sleep(0.8)
            back = screenshot()
            live = foreground_package() == PKG and match_visible(back)

    if not live:
        live = start_online_match()
    if not live:
        REPORT.skip("ONLINE-04", "online match has a voluntary exit", "online match not reachable")
    elif open_pause() is None:
        REPORT.failed("ONLINE-04", "online match has a voluntary exit", "match menu did not open")
    else:
        tap(*PAUSE_LEAVE)
        img = wait_screen("menu", 8.0)
        if screen_ok("menu", img):
            REPORT.passed("ONLINE-04", "online match has a voluntary exit", "menu -> leave returned to the main menu")
        else:
            img.save(RUN_DIR / "online_leave_failed.png", optimize=True)
            REPORT.failed("ONLINE-04", "online match has a voluntary exit", f"screen={classify(img)} after leave")

    if wifi_state != "COMPLETED":
        REPORT.skip(
            "NET-01",
            "second-device LAN join",
            f"Wi-Fi supplicant={wifi_state}; both devices must share a LAN (phone Wi-Fi is off)",
        )
    else:
        REPORT.skip("NET-01", "second-device LAN join", "single test device available; needs a second phone")


def run_log_checks() -> None:
    crash = adb(["logcat", "-b", "crash", "-d"], timeout=30)
    if PKG in crash or "fenghuoxiagu" in crash:
        REPORT.failed("LOG-01", "no native crash in crash buffer", crash.strip()[-300:])
    else:
        REPORT.passed("LOG-01", "no native crash in crash buffer", "empty")
    full = adb(["logcat", "-d", "-v", "brief"], timeout=40)
    fatal = [ln for ln in full.splitlines() if "FATAL EXCEPTION" in ln or "ANR in " + PKG in ln]
    if fatal:
        REPORT.failed("LOG-02", "no fatal exception / ANR", " | ".join(fatal[-3:]))
    else:
        REPORT.passed("LOG-02", "no fatal exception / ANR", "none")
    script_errors = [
        ln for ln in full.splitlines()
        if ("SCRIPT ERROR" in ln or "E Godot" in ln or "ERROR: " in ln)
        and ("godot" in ln.lower() or "fenghuoxiagu" in ln.lower() or "res://" in ln)
    ]
    if script_errors:
        REPORT.warn("LOG-03", "no Godot script errors", f"{len(script_errors)} lines; " + script_errors[-1][:200])
    else:
        REPORT.passed("LOG-03", "no Godot script errors", "none")

    shader_errors = [
        ln for ln in full.splitlines()
        if ("shader" in ln.lower() or "gles3" in ln.lower() or "opengl" in ln.lower())
        and ("error" in ln.lower() or "failed" in ln.lower() or "compile" in ln.lower())
        and ("godot" in ln.lower() or "fenghuo" in ln.lower())
    ]
    if shader_errors:
        REPORT.failed("RENDER-01", "no GLES3 shader compilation errors", shader_errors[-1][:200])
    else:
        REPORT.passed("RENDER-01", "no GLES3 shader compilation errors", "clean")

    try:
        audio_dump = sh("dumpsys audio | grep -iE 'player|stream|device'", timeout=15)
        if "STREAM_MUSIC" in audio_dump or "AudioPlayer" in audio_dump or "devices" in audio_dump:
            REPORT.passed("AUDIO-01", "audio subsystem active", "STREAM_MUSIC/device active")
        else:
            REPORT.warn("AUDIO-01", "audio subsystem active", "audio stream status unconfirmed")
    except Exception as exc:
        REPORT.warn("AUDIO-01", "audio subsystem active", str(exc))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-back", action="store_true", help="skip checks that intentionally leave the app")
    args = parser.parse_args()
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    print(f"device checks -> {RUN_DIR}", flush=True)
    try:
        info = run_static_checks()
    except Exception as exc:
        REPORT.failed("ENV-99", "static checks", f"{exc}\n{traceback.format_exc()[-500:]}")
        REPORT.write()
        return 2

    try:
        adb(["logcat", "-c"])
    except Exception:
        pass

    phases = [
        ("window", run_window_checks),
        ("video", run_video_checks),
        ("navigation", run_navigation_checks),
    ]
    if not args.skip_back:
        phases.append(("back", run_back_checks))
    phases += [
        ("match", run_match_and_input_checks),
        ("5v5", run_5v5_checks),
        ("online", lambda: run_online_host_checks(info.get("wifi", "unknown"))),
        ("logs", run_log_checks),
    ]
    for name, fn in phases:
        print(f"--- phase: {name}", flush=True)
        if not info.get("device_ok"):
            REPORT.skip(f"PHASE-{name.upper()}", f"{name} phase skipped", "device offline (static checks only)")
            continue
        if not ensure_device():
            REPORT.skip(f"PHASE-{name.upper()}", f"{name} phase skipped", "device offline (adb server restart failed)")
            continue
        try:
            fn()
        except ExternalInterference as exc:
            REPORT.skip(f"PHASE-{name.upper()}", f"{name} phase stopped", str(exc))
            log("another app kept the foreground; input was not sent")
            ensure_device()
            try:
                start_app()
            except Exception:
                pass
        except Exception as exc:
            REPORT.failed(f"PHASE-{name.upper()}", f"{name} phase aborted", f"{exc}\n{traceback.format_exc()[-800:]}")
            ensure_device()
            try:
                start_app()
            except Exception:
                pass

    REPORT.write()
    if not info.get("device_ok"):
        REPORT.skip("ENV-02", "device left at game menu", "device offline (static checks only)")
    else:
        try:
            if start_app():
                wait_screen("menu", 10.0)
            REPORT.info("ENV-02", "device left at game menu", f"top={foreground_package()}")
        except Exception as exc:
            REPORT.warn("ENV-02", "device left at game menu", str(exc))
    REPORT.write()
    s = {k: sum(1 for r in REPORT.rows if r["status"] == k) for k in ("PASS", "FAIL", "WARN", "SKIP", "INFO")}
    print("\nSUMMARY " + " ".join(f"{k}={v}" for k, v in s.items()))
    fails = [r for r in REPORT.rows if r["status"] == "FAIL"]
    if fails:
        print("FAILURES:")
        for r in fails:
            print(f"  {r['id']} {r['title']} -- {r['detail']}")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
