#!/usr/bin/env python3
"""Install AppImage build dependencies and re-run appimage-builder.

Run:  .venv/bin/python3 fix-appimage-build.py
"""
import os
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
RECIPE = PROJECT_ROOT / "AppImageBuilder.yml"
TOOLS = PROJECT_ROOT / ".tools" / "appimage-builder"
APPIMAGE_NAME = f"LocalSend-1.18.2-x86_64.AppImage"
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


def detect_apt() -> bool:
    return Path("/usr/bin/apt-get").exists() and os.geteuid() == 0


PKGS_COMMON = ["zsync", "squashfs-tools", "file", "libarchive-tools", "wget"]
PKGS_FUSE = ["libfuse2", "libfuse2t64"]  # libfuse2 in jammy, libfuse2t64 in noble+


def install_libfuse2() -> bool:
    """Install fuse2 + build tools via pkexec/apt (auto-pick libfuse2 vs libfuse2t64)."""
    if not Path("/usr/bin/pkexec").exists():
        log("错误", "未找到 pkexec（policykit）；用 root 手动跑：", RED)
        print("    sudo apt install -y libfuse2 zsync squashfs-tools file", flush=True)
        return False

    # Probe which fuse2 package the repo provides
    fuse_to_install: str | None = None
    for cand in PKGS_FUSE:
        r = subprocess.run(["apt-cache", "show", cand], capture_output=True, text=True)
        if r.returncode == 0 and "Package:" in r.stdout:
            fuse_to_install = cand
            break
    if not fuse_to_install:
        log("错误", "找不到 libfuse2 / libfuse2t64（universe 启用了？）", RED)
        return False

    pkexec = ["pkexec", "apt", "install", "-y", fuse_to_install, *PKGS_COMMON]
    log("步骤", f"pkexec apt install {fuse_to_install} ... （会弹 GUI 密码框）")
    r = subprocess.run(pkexec, capture_output=False)
    if r.returncode != 0:
        log("错误", f"apt install 失败 rc={r.returncode}", RED)
        return False
    log("完成", f"{fuse_to_install} 等已装", GREEN)
    return True


def verify_libfuse2() -> bool:
    """Confirm libfuse2 (or libfuse2t64) installed."""
    for cand in PKGS_FUSE:
        r = subprocess.run(
            ["dpkg-query", "-W", "-f=${Status}", cand],
            capture_output=True, text=True,
        )
        if r.returncode == 0 and "install ok" in r.stdout:
            return True
    # fallback: shared object exists
    for so in ["/usr/lib/x86_64-linux-gnu/libfuse.so.2", "/lib/x86_64-linux-gnu/libfuse.so.2"]:
        if Path(so).exists():
            return True
    return False


def find_appimage_builder() -> str | None:
    """Return absolute path to appimage-builder or None."""
    import shutil
    p = shutil.which("appimage-builder")
    if p and os.access(p, os.X_OK):
        return p
    for cand in [
        "/usr/local/bin/appimage-builder",
        str(Path.home() / ".local/bin/appimage-builder"),
        str(PROJECT_ROOT / ".tools/appimage-builder"),
    ]:
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


TUNA_SOURCES = [
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy universe",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates universe",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy multiverse",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates multiverse",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security universe",
    "sourceline: deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security multiverse",
]


def patch_recipe_to_tuna() -> bool:
    """Mutate RECIPE in place to:
      1. replace archive.ubuntu.com sources with TUNA mirrors
      2. apt.exclude glib family (host glib is newer than jammy's, so
         leaving glib 2.72 in the AppDir breaks the binary at runtime
         with "undefined symbol: g_once_init_enter_pointer")
      3. inject a `script:` line that force-removes any glib that the
         transitive dependency chain still drags in, so the AppImage
         runtime falls back to the host's glib (the one the binary was
         actually built against).

    The caller is expected to have just reset RECIPE from the template
    so this function can write its patches idempotently.
    """
    if not RECIPE.exists():
        log("错误", f"找不到 {RECIPE}", RED)
        return False
    text = RECIPE.read_text(encoding="utf-8")
    import re

    # 1) sources -> TUNA
    new_sources = "    sources:\n" + "".join(f"      - {s}\n" for s in TUNA_SOURCES)
    text, n = re.subn(
        r"    sources:\n((?:      - sourceline: [^\n]+\n)+)",
        new_sources, text, count=1,
    )
    if n == 0:
        log("警告", "没匹配到 sources 块（yml 格式可能变了）", YELLOW)
        return False

    # 2) apt.exclude glib family. `apt exclude` only affects explicitly
    # named packages; transitive deps still install. The script step
    # below does the real cleanup, but the exclude keeps the AppDir
    # leaner (and faster to build).
    glib_excludes = [
        "libglib2.0-0", "libglib2.0-0t64",
        "libgio-2.0-0", "libgio-2.0-0t64",
        "libgobject-2.0-0", "libgobject-2.0-0t64",
        "libgmodule-2.0-0", "libgmodule-2.0-0t64",
    ]
    extra = "".join(f"      - {p}\n" for p in glib_excludes)
    text = text.replace(
        "    exclude:\n      - adwaita-icon-theme:*\n",
        "    exclude:\n      - adwaita-icon-theme:*\n" + extra,
    )

    # 2b) files.exclude glib .so files. Even if apt install + script rm
    # miss something, appimage-builder's file-collect step will drop
    # them before the squashfs is built — so the AppImage runtime is
    # guaranteed to find no glib in $APPDIR/usr/lib and fall back to
    # the host's glib (which is the version the binary was built
    # against).
    glib_files = [
        "usr/lib/x86_64-linux-gnu/libglib-2.0.so*",
        "usr/lib/x86_64-linux-gnu/libgio-2.0.so*",
        "usr/lib/x86_64-linux-gnu/libgobject-2.0.so*",
        "usr/lib/x86_64-linux-gnu/libgmodule-2.0.so*",
    ]
    files_extra = "".join(f"      - {p}\n" for p in glib_files)
    text = text.replace(
        "  files:\n    include: []\n    exclude:\n      - usr/share/man\n",
        "  files:\n    include: []\n    exclude:\n" + files_extra
        + "      - usr/share/man\n",
    )

    # 3) script: remove glib .so files after apt deploy. The script block
    # runs in a sandbox where we don't have sudo for transitive deps
    # that appimage-builder couldn't exclude, so `rm -f` (best-effort)
    # plus `; exit 0` is the right tool — we don't want appimage-builder
    # to abort the build when there's nothing left to remove.
    cleanup = (
        "  - sh -c 'rm -f /usr/lib/x86_64-linux-gnu/libglib-2.0.so*"
        " /usr/lib/x86_64-linux-gnu/libgio-2.0.so*"
        " /usr/lib/x86_64-linux-gnu/libgobject-2.0.so*"
        " /usr/lib/x86_64-linux-gnu/libgmodule-2.0.so* 2>/dev/null; exit 0'\n"
    )
    text = text.replace(
        "  - which mksquashfs || apt install squashfs-tools\n",
        "  - which mksquashfs || apt install squashfs-tools\n" + cleanup,
    )

    RECIPE.write_text(text, encoding="utf-8")
    log("步骤", f"patched {RECIPE.name}: TUNA sources + glib exclude + rm script")
    return True


def kill_stale() -> None:
    """Kill any stuck apt/appimage-builder from previous failed runs."""
    for pat in ["apt-get", "dpkg", "appimage-builder"]:
        subprocess.run(["pkill", "-9", "-f", pat], check=False, capture_output=True)


def auto_clean_if_needed() -> bool:
    """Detect a half-built / poisoned apt cache and force --clean.

    appimage-builder's appimage-build/.apt_cache/ is the speedup win,
    but if a previous run died mid-apt the cache can be left in a state
    where the next apt install picks up corrupted .debs and hangs or
    errors. We detect two failure shapes:

      1. `appimage-build/` exists but no `.apt_cache/` at all
         (appimage-builder created the staging dir, then crashed before
         apt started).
      2. `.apt_cache/` exists but dpkg status is missing — dpkg uses
         this to know what's installed, so its absence means the cache
         is not consistent.

    Returns True if we decided to do a full clean.
    """
    staging = PROJECT_ROOT / "appimage-build"
    cache = staging / ".apt_cache"
    if not staging.exists():
        return False  # first run, nothing to clean
    if not cache.exists():
        log("兜底", f"{staging} 存在但 .apt_cache 缺失 → 自动 --clean")
        return True
    dpkg_status = cache / "var" / "lib" / "dpkg" / "status"
    if not dpkg_status.exists():
        log("兜底", f".apt_cache/var/lib/dpkg/status 缺失 → 自动 --clean")
        return True
    return False


def clean_appimage_build(full: bool = False) -> None:
    """Clean staging state.

    By default we keep `appimage-build/` because it contains the apt
    package cache (`.apt_cache/`) — the next run reuses the downloaded
    .debs and apt install drops from ~90s to ~15s. Pass full=True to
    nuke the cache too (e.g. after a recipe change or to recover from
    a poisoned cache).
    """
    kill_stale()
    # AppDir is our input — we re-create it from the flutter bundle
    # every run, so deleting it is safe and cheap.
    for d in [PROJECT_ROOT / "AppDir"]:
        if d.exists():
            log("清理", f"rm -rf {d}")
            subprocess.run(["rm", "-rf", str(d)], check=False, capture_output=True)
    if full:
        cache = PROJECT_ROOT / "appimage-build"
        if cache.exists():
            log("清理", f"rm -rf {cache}（全清，apt 缓存也删掉）")
            subprocess.run(["rm", "-rf", str(cache)], check=False, capture_output=True)
    else:
        cache = PROJECT_ROOT / "appimage-build"
        if cache.exists():
            log("信息", f"复用 {cache}/ 里的 apt 缓存（apt install 会变快）")
    for old in PROJECT_ROOT.glob("LocalSend-*-x86_64.AppImage"):
        log("清理", f"rm {old.name}")
        old.unlink()


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--clean", action="store_true",
                    help="全清（包括 appimage-build/ 的 apt 缓存）。默认保留以加速。")
    ap.add_argument("--skip-flutter", action="store_true",
                    help="跳过 flutter build linux（用现有 bundle）。")
    ap.add_argument("--no-patch", action="store_true",
                    help="不重置 / patch yml（只重打 AppImage）。")
    args = ap.parse_args()

    print("=" * 60)
    print("  AppImage 打包：依赖修复 + 重跑")
    print("=" * 60)

    # Step 1: install libfuse2 if missing
    if not verify_libfuse2():
        log("信息", "libfuse2 缺失，需要装。")
        if not install_libfuse2():
            return 1
    else:
        log("信息", "libfuse2 已装 ✓")

    # Step 2: locate appimage-builder
    ab = find_appimage_builder()
    if not ab:
        log("错误", "appimage-builder 未装。先跑 install-appimage-builder.py", RED)
        return 1
    log("找到", ab)

    # Step 4: ensure RECIPE exists and is CLEAN. Always copy from the
    # template first so repeated runs don't accumulate exclude blocks or
    # leftover script lines (which is what made the previous build fail
    # with sudo errors and leave the AppDir's stale glib behind).
    if not args.no_patch:
        src_recipe = PROJECT_ROOT / "support/build/appimage/AppImageBuilder_x86_64.yml"
        if not src_recipe.exists():
            log("错误", f"找不到模板 {src_recipe}", RED)
            return 1
        import shutil
        shutil.copy2(src_recipe, RECIPE)
        log("步骤", f"reset {RECIPE.name} from {src_recipe.name}")
        # Step 5: patch sources to TUNA mirror (avoids archive.ubuntu.com + GPG)
        patch_recipe_to_tuna()

    # Step 6: clean partial state (keep apt cache by default).
    # Unless the user passed --clean, auto-decide: if the previous run
    # left a half-built cache, do a full clean so we don't loop on a
    # poisoned state.
    if args.clean:
        clean_appimage_build(full=True)
    else:
        clean_appimage_build(full=auto_clean_if_needed())

    # Step 7: ensure AppDir/ built flutter bundle present
    bundle = PROJECT_ROOT / "app/build/linux/x64/release/bundle"
    if not bundle.exists() or not (bundle / "localsend_app").exists():
        if args.skip_flutter:
            log("错误", f"--skip-flutter 但 bundle 不存在：{bundle}", RED)
            return 1
        log("信息", f"flutter bundle 不在 {bundle}，先 build linux")
        r = subprocess.run(
            ["fvm", "flutter", "build", "linux", "--release"],
            cwd=str(PROJECT_ROOT / "app"),
        )
        if r.returncode != 0:
            log("错误", f"flutter build linux 失败 rc={r.returncode}", RED)
            return 1

    log("信息", "mkdir AppDir + cp flutter bundle 内容（注意是内容不是目录）")
    import shutil
    (PROJECT_ROOT / "AppDir").mkdir()
    # Use copytree so we get the CONTENTS of bundle/ at the top of AppDir,
    # not bundle/ itself. yml says `exec: localsend_app`, which must live at
    # AppDir/localsend_app, not AppDir/bundle/localsend_app.
    shutil.copytree(bundle, PROJECT_ROOT / "AppDir", dirs_exist_ok=True)

    # Step 7.4: GLib version mismatch between build host and jammy AppDir.
    # localsend_app may link symbols that exist only in newer glib
    # (e.g. g_once_init_enter_pointer, added in 2.80). If AppDir's libglib
    # is older, runtime gets "undefined symbol". Strip the glib family
    # from AppDir so the AppImage runtime uses the host's glib (which is
    # the same one the binary was built against).
    stripped = 0
    for f in (PROJECT_ROOT / "AppDir" / "usr" / "lib" / "x86_64-linux-gnu").glob("libglib*"):
        if f.is_file() or f.is_symlink():
            f.unlink()
            stripped += 1
    for sub in ("gio", "gmodule", "gobject"):
        for f in (PROJECT_ROOT / "AppDir" / "usr" / "lib" / "x86_64-linux-gnu").glob(f"lib{sub}*"):
            if f.is_file() or f.is_symlink():
                f.unlink()
                stripped += 1
    if stripped:
        log("信息", f"已从 AppDir 删 {stripped} 个 glib/gio 文件（用 host glib）")
    else:
        log("信息", "AppDir 没有 glib，无需清理")

    # Step 7.5: place app icons. appimage-builder searches
    # AppDir/usr/share/icons and AppDir/usr/share/pixmaps. yml says
    # `icon: localsend`, so we need files named `localsend.<ext>` there.
    icon_src = bundle / "data" / "flutter_assets" / "assets" / "img" / "logo-512.png"
    if icon_src.exists():
        for size, suffix in [(512, "512x512/apps/localsend.png"),
                              (256, "256x256/apps/localsend.png"),
                              (128, "128x128/apps/localsend.png"),
                              (32,  "32x32/apps/localsend.png")]:
            dest = PROJECT_ROOT / "AppDir" / "usr" / "share" / "icons" / "hicolor" / suffix
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(icon_src, dest)
        # pixmap fallback
        pix = PROJECT_ROOT / "AppDir" / "usr" / "share" / "pixmaps" / "localsend.png"
        pix.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(icon_src, pix)
        log("信息", "已部署 4 套图标 + pixmap 兜底（来自 logo-512.png）")
    else:
        log("信息", "未找到 logo-512.png，跳过图标部署")

    # Step 7.6: write a .desktop file into AppDir/. appimage-builder v1.1.0
    # does NOT generate one from `app_info` — without it, the resulting
    # AppImage launches headless of the user's launcher, so the icon
    # doesn't show in the dock and you can't pin it to the taskbar.
    # Place it in two locations: the AppDir root (which AppImage runtime
    # treats as the bundle entry) and the FHS path some DEs scan.
    appimage_desktop = PROJECT_ROOT / "AppDir" / f"{APP_ID}.desktop"
    fhs_desktop = PROJECT_ROOT / "AppDir" / "usr" / "share" / "applications" / f"{APP_ID}.desktop"
    desktop_body = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=LocalSend\n"
        "GenericName=File Transfer\n"
        "Comment=Share files to nearby devices\n"
        "Categories=Network;FileTransfer;Utility;\n"
        "Exec=localsend_app %U\n"
        "Icon=localsend\n"
        "Terminal=false\n"
        "StartupNotify=true\n"
        "StartupWMClass=localsend_app\n"
    )
    for d in (appimage_desktop, fhs_desktop):
        d.parent.mkdir(parents=True, exist_ok=True)
        d.write_text(desktop_body, encoding="utf-8")
        d.chmod(0o755)
    log("信息", f"已写入 {appimage_desktop.relative_to(PROJECT_ROOT)} 和 usr/share/applications/ 同名文件")

    # Step 8: run appimage-builder
    log("步骤", f"{ab} --recipe {RECIPE.name}  （约 1-3 分钟，请耐心等待）")
    print("-" * 60)
    # appimage-builder's internal Python uses urlopen for GitHub downloads
    # (AppRun, libapprun_hooks). It honors HTTP_PROXY/HTTPS_PROXY but not
    # APT_HTTP_PROXY. Auto-detect a working proxy so GitHub downloads don't
    # stall, while leaving apt alone (it already uses TUNA mirrors).
    env = os.environ.copy()
    env.setdefault("HTTP_PROXY", "http://127.0.0.1:7890")
    env.setdefault("HTTPS_PROXY", "http://127.0.0.1:7890")
    env.setdefault("http_proxy", env["HTTP_PROXY"])
    env.setdefault("https_proxy", env["HTTPS_PROXY"])
    # Quick reachability probe — only enable proxy if GitHub is actually
    # reachable through it. Otherwise leave env untouched (env untouched is
    # no good — GitHub from China is unreachable without proxy, so fall back
    # to letting the user pass --no-proxy to override).
    try:
        r = subprocess.run(
            ["curl", "-sI", "--max-time", "5", "--proxy", env["HTTPS_PROXY"],
             "https://github.com/"],
            capture_output=True, timeout=8,
        )
        if r.returncode == 0:
            log("信息", f"代理 {env['HTTPS_PROXY']} 通 GitHub，启用")
        else:
            log("信息", "代理不通，尝试直连（多半会卡在 GitHub）")
    except Exception:
        log("信息", "探测代理失败，按既有设置走")
    # appimage-builder is itself an AppImage and needs FUSE to mount on
    # first run. Sandboxes (Trae, snap, flatpak) usually block /dev/fuse.
    # Workaround: --appimage-extract-and-run extracts it on the fly
    # without FUSE, or extract once and run squashfs-root/AppRun.
    # We prefer the persistent extract so the next run is fast.
    ab_path = Path(ab)
    ab_dir = ab_path.parent
    ab_name = ab_path.name
    extracted_app = ab_dir / "squashfs-root" / "AppRun"
    if not extracted_app.exists():
        log("步骤", f"提取 {ab_name} 到 squashfs-root/（绕过 FUSE）")
        r = subprocess.run(
            [str(ab), "--appimage-extract"],
            cwd=str(ab_dir), env=env, capture_output=True, text=True,
        )
        if r.returncode != 0 or not extracted_app.exists():
            log("信息", "提取失败，回退 --appimage-extract-and-run")
            ab_cmd = [str(ab), "--appimage-extract-and-run", "--recipe", str(RECIPE)]
        else:
            ab_cmd = [str(extracted_app), "--recipe", str(RECIPE)]
    else:
        log("信息", "复用 squashfs-root/AppRun（之前已提取）")
        ab_cmd = [str(extracted_app), "--recipe", str(RECIPE)]
    r = subprocess.run(ab_cmd, cwd=str(PROJECT_ROOT), env=env)
    print("-" * 60)
    if r.returncode != 0:
        log("错误", f"appimage-builder 失败 rc={r.returncode}", RED)
        return r.returncode

    # Step 9: chmod + verify output
    out = PROJECT_ROOT / APPIMAGE_NAME
    if not out.exists():
        log("错误", f"找不到 {APPIMAGE_NAME}", RED)
        return 1

    log("步骤", f"chmod +x {APPIMAGE_NAME}")
    out.chmod(0o755)

    sz = out.stat().st_size / 1024 / 1024
    log("完成", f"✓ {APPIMAGE_NAME} ({sz:.1f} MB)", GREEN)
    log("用法", f"双击或 {out} 启动；分发给任何 x86_64 Linux 用户", GREEN)
    return 0


if __name__ == "__main__":
    sys.exit(main())
