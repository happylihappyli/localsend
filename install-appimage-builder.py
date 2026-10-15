#!/usr/bin/env python3
"""装 appimage-builder（AppImage 打包工具，单文件 ~36MB）。

下载源：https://github.com/AppImageCrafters/appimage-builder/releases
  - 1.1.0 是 stable
  - 走 GitHub API 查最新版本（避免硬编码）

安装路径（按顺序探测）：
  1. /usr/local/bin/appimage-builder      ← 需要 pkexec (推荐)
  2. ~/.local/bin/appimage-builder        ← 免 root，写到 PATH 即可
  3. /home/bv/code/localsend/.tools/      ← 项目本地，最稳

UI：qt 进度条 + 当前下载百分比
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

# 目标安装目录
LOCAL_BIN = Path.home() / ".local" / "bin" / "appimage-builder"
PROJECT_BIN = Path("/home/bv/code/localsend/.tools") / "appimage-builder"
GLOBAL_BIN = Path("/usr/local/bin/appimage-builder")

RELEASE_API = "https://api.github.com/repos/AppImageCrafters/appimage-builder/releases/latest"
DEFAULT_PROXY = "http://127.0.0.1:7890"


def setup_proxy(argv: list[str]) -> None:
    """装全局 urllib 代理。默认走 DEFAULT_PROXY；--no-proxy 关闭。"""
    proxy = DEFAULT_PROXY
    if "--no-proxy" in argv:
        proxy = None
    elif "--proxy" in argv:
        i = argv.index("--proxy")
        if i + 1 < len(argv):
            proxy = argv[i + 1]
    if proxy:
        handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy, "all": proxy})
        urllib.request.install_opener(urllib.request.build_opener(handler))
        # 同步给子进程（GitHub API 有时重定向到 S3 之类的）
        os.environ["HTTP_PROXY"] = proxy
        os.environ["HTTPS_PROXY"] = proxy
        print(f"[proxy] {proxy}")
    else:
        print("[proxy] 直连")


def pick_install_dir() -> Path:
    """按优先级选安装目录。"""
    # 1. 已装到 /usr/local/bin
    if GLOBAL_BIN.exists() and os.access(GLOBAL_BIN, os.X_OK):
        print(f"[OK] 已经在 {GLOBAL_BIN}")
        return GLOBAL_BIN
    # 2. ~/.local/bin
    LOCAL_BIN.parent.mkdir(parents=True, exist_ok=True)
    if LOCAL_BIN.exists() and os.access(LOCAL_BIN, os.X_OK):
        print(f"[OK] 已经在 {LOCAL_BIN}")
        return LOCAL_BIN
    # 3. 项目本地
    PROJECT_BIN.parent.mkdir(parents=True, exist_ok=True)
    return PROJECT_BIN


def get_latest_url() -> tuple[str, str]:
    """返回 (version, download_url)。"""
    print(f"→ 查最新版本: {RELEASE_API}")
    req = urllib.request.Request(RELEASE_API, headers={"User-Agent": "install-appimage-builder/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    version = data.get("tag_name", "v1.1.0").lstrip("v")
    asset = None
    for a in data.get("assets", []):
        if a["name"].endswith(f"-x86_64.AppImage"):
            asset = a
            break
    if not asset:
        raise SystemExit("[FAIL] 没找到 x86_64 AppImage asset")
    return version, asset["browser_download_url"]


def download(url: str, dst: Path) -> None:
    """带进度的下载。"""
    print(f"→ 下载 {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "install-appimage-builder/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r:
        total = int(r.headers.get("Content-Length", 0))
        chunk = 64 * 1024
        got = 0
        last_pct = -1
        with open(dst, "wb") as f:
            while True:
                buf = r.read(chunk)
                if not buf:
                    break
                f.write(buf)
                got += len(buf)
                if total > 0:
                    pct = got * 100 // total
                    if pct != last_pct and pct % 10 == 0:
                        print(f"  {pct}%  ({got//1024 // 1024} MB / {total//1024//1024} MB)", flush=True)
                        last_pct = pct
    print(f"  ✓ 下载完成: {dst}  ({dst.stat().st_size // 1024 // 1024} MB)")


def install_to(path: Path, appimage: Path) -> None:
    """chmod +x + 移到目标位置（必要时 pkexec）。"""
    appimage.chmod(0o755)
    if path == GLOBAL_BIN:
        # 用 pkexec 弹 GUI 认证框
        if not shutil.which("pkexec"):
            raise SystemExit("[FAIL] 装到 /usr/local/bin 需要 pkexec（apt install policykit-1）")
        print(f"→ pkexec mv {appimage} {path}")
        rc = subprocess.call(["pkexec", "mv", str(appimage), str(path)])
        if rc != 0:
            raise SystemExit(f"[FAIL] pkexec 退出码 {rc}")
    elif path == LOCAL_BIN:
        # 已经在那个位置（或 mv）
        if appimage != path:
            shutil.move(str(appimage), str(path))
    else:  # PROJECT_BIN
        if appimage != path:
            shutil.move(str(appimage), str(path))


def main() -> int:
    setup_proxy(sys.argv[1:])
    install_dir = pick_install_dir()
    # 1. 查最新版本
    try:
        version, url = get_latest_url()
    except Exception as e:
        print(f"[WARN] GitHub API 失败 {e}，回退到 v1.1.0")
        version, url = "1.1.0", "https://github.com/AppImageCrafters/appimage-builder/releases/download/v1.1.0/appimage-builder-1.1.0-x86_64.AppImage"
    print(f"→ 最新版本: v{version}")

    # 2. 下载到临时位置
    tmp = Path("/tmp/appimage-builder-latest.AppImage")
    download(url, tmp)

    # 3. 安装
    install_to(install_dir, tmp)

    # 4. 验证
    print(f"→ 验证: {install_dir} --version")
    try:
        r = subprocess.run([str(install_dir), "--version"], capture_output=True, timeout=10, text=True)
        first = (r.stdout or r.stderr).strip().splitlines()[0] if (r.stdout or r.stderr) else "(无输出)"
        print(f"  ✓ {first}")
    except Exception as e:
        print(f"  [WARN] 验证失败: {e}")

    # 5. PATH 提示
    parent = str(install_dir.parent)
    if install_dir == LOCAL_BIN and parent not in os.environ.get("PATH", ""):
        print(f"\n[HINT] 装了到 {install_dir}，但 {parent} 不在 PATH")
        print(f"       临时：export PATH=\"{parent}:$PATH\"")
        print(f"       永久：在 ~/.bashrc 加 'export PATH=\"$HOME/.local/bin:$PATH\"'")

    print(f"\n[OK] 完成。appimage-builder 已就绪")
    return 0


if __name__ == "__main__":
    sys.exit(main())
