#!/usr/bin/env python3
"""Register an already-built LocalSend AppImage with the user's desktop.

Extracts the AppImage (or reuses squashfs-root/), copies the .desktop file
and icons into ~/.local/share/, so GNOME/KDE/XFCE can show the icon and
let the user pin it to the taskbar / dock.

Run:
    .venv/bin/python3 install-appimage-desktop.py
    .venv/bin/python3 install-appimage-desktop.py --appimage /path/to/LocalSend-1.18.2-x86_64.AppImage
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_APPIMAGE = PROJECT_ROOT / "LocalSend-1.18.2-x86_64.AppImage"
APP_ID = "org.localsend.localsend_app"

GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"


def log(tag: str, msg: str, color: str = ""):
    if color:
        print(f"{color}[{tag}]{RESET} {msg}", flush=True)
    else:
        print(f"[{tag}] {msg}", flush=True)


def find_squashfs_root(appimage: Path) -> Path:
    """Prefer existing squashfs-root/ next to the AppImage; otherwise
    extract the AppImage (bypassing FUSE for sandboxed envs)."""
    candidate = appimage.parent / "squashfs-root"
    if (candidate / "AppRun").exists():
        return candidate
    log("步骤", f"提取 {appimage.name} → squashfs-root/")
    # --appimage-extract is FUSE-free and works in sandboxes that block
    # /dev/fuse. The trailing "2>&1 | tail" keeps output bounded.
    subprocess.run([str(appimage), "--appimage-extract"],
                   cwd=str(appimage.parent), check=True)
    return candidate


def install_desktop(squashfs: Path, appimage: Path) -> int:
    """Copy .desktop + icons into ~/.local/share/ and update databases."""
    home = Path.home()
    apps_dir = home / ".local" / "share" / "applications"
    icons_dir = home / ".local" / "share" / "icons" / "hicolor"
    apps_dir.mkdir(parents=True, exist_ok=True)

    # Locate the .desktop inside the AppImage. appimage-builder doesn't
    # generate it (recipe `app_info` is only metadata for the runtime),
    # so the file may be missing. We try the canonical names anyway, and
    # if absent we create a minimal one.
    desktop_src = None
    for name in (f"{APP_ID}.desktop", "localsend.desktop"):
        p = squashfs / "usr" / "share" / "applications" / name
        if p.exists():
            desktop_src = p
            break
    if desktop_src is None:
        for p in squashfs.rglob("*.desktop"):
            desktop_src = p
            break

    desktop_dst = apps_dir / f"{APP_ID}.desktop"
    if desktop_src is not None:
        shutil.copy2(desktop_src, desktop_dst)
        log("信息", f"复制 {desktop_src.relative_to(squashfs)} → ~/.local/share/applications/")
    else:
        log("信息", "AppImage 内未找到 .desktop，手写一个")
        desktop_dst.write_text(_make_desktop(appimage), encoding="utf-8")

    # Always rewrite Exec= to the absolute AppImage path (the bundled
    # .desktop may use AppRun or a relative path that doesn't survive
    # being moved to ~/.local/share/applications/).
    text = desktop_dst.read_text(encoding="utf-8")
    import re
    text = re.sub(r"^Exec=.*$", f"Exec={appimage} %U", text, flags=re.M)
    text = re.sub(r"^TryExec=.*$", f"TryExec={appimage}", text, flags=re.M)
    text = re.sub(r"^Icon=.*$", f"Icon={APP_ID}", text, flags=re.M)
    desktop_dst.write_text(text, encoding="utf-8")
    desktop_dst.chmod(0o755)
    log("信息", f"修正 Exec=/Icon= → {appimage.name}")

    # Copy icons out of the AppImage to hicolor so the DE finds them.
    n_icons = _install_icons(squashfs, icons_dir)
    log("信息", f"安装 {n_icons} 个图标到 ~/.local/share/icons/hicolor/")

    # Refresh the desktop / icon caches so the change is visible
    # without re-login.
    for cmd in [
        ["update-desktop-database", str(apps_dir)],
        ["gtk-update-icon-cache", "-f", "-t", str(icons_dir)],
    ]:
        try:
            subprocess.run(cmd, capture_output=True, check=False)
        except FileNotFoundError:
            pass  # missing helper is fine on minimal distros

    log("完成", f"✓ {APP_ID} 已注册到用户桌面", GREEN)
    log("用法", "在应用菜单/启动器里搜「LocalSend」即可固定到任务栏", GREEN)
    return 0


def _make_desktop(appimage: Path) -> str:
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name=LocalSend\n"
        f"Exec={appimage} %U\n"
        f"TryExec={appimage}\n"
        f"Icon={APP_ID}\n"
        "Comment=Share files to nearby devices\n"
        "Categories=Network;FileTransfer;Utility;\n"
        "Terminal=false\n"
        "StartupNotify=true\n"
        "StartupWMClass=localsend_app\n"
    )


def _install_icons(squashfs: Path, icons_dir: Path) -> int:
    """Copy every icon named localsend* (any size) into hicolor/apps/."""
    count = 0
    # 1) look for icons in the standard places
    candidates = []
    for sub in squashfs.glob("usr/share/icons/hicolor/*/apps/localsend*"):
        candidates.append(sub)
    for sub in squashfs.glob("usr/share/pixmaps/localsend*"):
        candidates.append(sub)
    for src in candidates:
        size_dir = "scalable" if "scalable" in str(src) else src.parent.name
        dst = icons_dir / size_dir / "apps" / src.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        count += 1
    if count:
        return count
    # 2) fallback: extract the Flutter logo from the bundle inside the
    # AppImage and drop it at 512x512.
    for logo in squashfs.glob("data/flutter_assets/assets/img/logo-512.png"):
        dst = icons_dir / "512x512" / "apps" / f"{APP_ID}.png"
        dst_alt = icons_dir / "scalable" / "apps" / f"{APP_ID}.png"
        for d in (dst, dst_alt):
            d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(logo, dst)
        shutil.copy2(logo, dst_alt)
        count = 2
        break
    return count


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--appimage", type=Path, default=DEFAULT_APPIMAGE,
                    help=f"AppImage 路径（默认 {DEFAULT_APPIMAGE.name}）")
    args = ap.parse_args()

    if not args.appimage.exists():
        log("错误", f"找不到 {args.appimage}", RED)
        return 1

    try:
        squashfs = find_squashfs_root(args.appimage)
    except subprocess.CalledProcessError as e:
        log("错误", f"提取失败 rc={e.returncode}", RED)
        return 1

    if not (squashfs / "AppRun").exists():
        log("错误", f"{squashfs} 不是有效的 AppImage 目录", RED)
        return 1

    return install_desktop(squashfs, args.appimage)


if __name__ == "__main__":
    sys.exit(main())
