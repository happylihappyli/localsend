#!/usr/bin/env python3
"""LocalSend Flutter 编译 / 检查的 GUI 启动器。

点击按钮触发对应的 `fvm` 命令，stdout 实时写到文本框里。
执行时按钮自动 disable，完成后恢复，避免并发跑命令。

用法:
    python3 ui.py
"""

import html
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time

try:
    from PySide6.QtCore import Qt, QSize, QTimer
    from PySide6.QtGui import QAction, QColor, QFont, QIcon, QKeySequence, QPixmap, QShortcut, QTextCharFormat, QTextCursor
    from PySide6.QtWidgets import (
        QApplication,
        QCheckBox,
        QDialog,
        QDialogButtonBox,
        QFormLayout,
        QFrame,
        QGridLayout,
        QGroupBox,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMainWindow,
        QPlainTextEdit,
        QPushButton,
        QScrollArea,
        QSizePolicy,
        QSplitter,
        QStatusBar,
        QStyle,
        QTabWidget,
        QTextEdit,
        QVBoxLayout,
        QWidget,
    )
except ImportError as e:
    print(f"[ui.py] 错误：缺少 PySide6（{e}）", file=sys.stderr)
    print("", file=sys.stderr)
    print("ui.py 用 PySide6 写 GUI。安装：", file=sys.stderr)
    print("  pip install --user PySide6", file=sys.stderr)
    print("或走代理：", file=sys.stderr)
    print("  pip install --user --proxy http://127.0.0.1:7890 PySide6", file=sys.stderr)
    sys.exit(2)

PROJECT_ROOT = "/home/bv/code/localsend"
APP_DIR = os.path.join(PROJECT_ROOT, "app")
ISOLATES_DIR = os.path.join(PROJECT_ROOT, "packages", "localsend_isolates")
TYPED_ISOLATES_DIR = os.path.join(PROJECT_ROOT, "packages", "typed_isolates")
RUST_ISOLATES_DIR = os.path.join(ISOLATES_DIR, "rust")
CORE_DIR = os.path.join(PROJECT_ROOT, "packages", "core")


# ── 全局样式表（QSS）─────────────────────────────────────────────
# GitHub Light 配色 + 暗色输出区。tab 顶部对齐按钮框。
# 设计要点：
#  - GroupBox 圆角 10 + 浅色背景 + 标题 11pt 半粗 + 灰底胶囊
#  - 主按钮扁平风，hover 渐深，chain 按钮主色 (蓝) 突出
#  - tab 选中态：白底 + 蓝字 + 加粗 + 下划线
#  - 状态栏三段（自动延伸 + 永久 widget）
#  - 暗色输出区：等宽字体、圆角 8、行高 1.25
QSS = """
QMainWindow { background: #f6f8fa; }
QGroupBox {
    border: 1px solid #d0d7de;
    border-radius: 10px;
    margin-top: 16px;
    padding: 14px 12px 10px 12px;
    background: #ffffff;
    font-weight: 600;
    color: #1f2328;
}
QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    left: 12px;
    padding: 2px 10px;
    color: #1f2328;
    background: #eaeef2;
    border-radius: 4px;
    font-size: 11pt;
}
QPushButton {
    background: #f6f8fa;
    border: 1px solid #d0d7de;
    border-radius: 8px;
    padding: 7px 14px;
    color: #1f2328;
    text-align: left;
    min-height: 20px;
    font-size: 10pt;
}
QPushButton:hover { background: #eaeef2; border-color: #afb8c1; }
QPushButton:pressed { background: #d0d7de; }
QPushButton:disabled { background: #f6f8fa; color: #afb8c1; border-color: #eaeef2; }
QPushButton#primary {
    background: #0969da;
    color: #ffffff;
    border: 1px solid #0969da;
    font-weight: 600;
}
QPushButton#primary:hover { background: #0860c7; border-color: #0860c7; }
QPushButton#primary:pressed { background: #0757b3; }
QPushButton#primary:disabled { background: #b6d4f4; color: #ffffff; border-color: #b6d4f4; }
QLineEdit {
    border: 1px solid #d0d7de;
    border-radius: 6px;
    padding: 5px 9px;
    background: #ffffff;
    selection-background-color: #0969da;
    selection-color: #ffffff;
    font-size: 10pt;
}
QLineEdit:focus { border-color: #0969da; }
QCheckBox { color: #1f2328; spacing: 6px; font-size: 10pt; }
QCheckBox::indicator { width: 16px; height: 16px; }
QTabWidget::pane {
    border: 1px solid #d0d7de;
    border-top-right-radius: 10px;
    border-bottom-left-radius: 10px;
    border-bottom-right-radius: 10px;
    background: #ffffff;
    top: -1px;
}
QTabBar::tab {
    padding: 8px 18px;
    background: #f6f8fa;
    border: 1px solid #d0d7de;
    border-bottom: none;
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
    color: #57606a;
    margin-right: 3px;
    font-size: 10pt;
}
QTabBar::tab:hover { background: #eaeef2; color: #1f2328; }
QTabBar::tab:selected {
    background: #ffffff;
    color: #0969da;
    font-weight: 700;
    border-bottom: 1px solid #ffffff;
    /* 下划线效果：用 padding-bottom + 背景色边框 */
    padding-bottom: 9px;
}
QStatusBar {
    background: #f6f8fa;
    color: #57606a;
    border-top: 1px solid #d0d7de;
    font-size: 9pt;
}
QStatusBar::item { border: none; }
QStatusBar QLabel { padding: 0 8px; }
QPlainTextEdit, QTextEdit {
    background: #0d1117;
    color: #c9d1d9;
    border: 1px solid #30363d;
    border-radius: 10px;
    padding: 8px 10px;
    font-family: "JetBrains Mono", "Source Code Pro", "Cascadia Code", "Courier New", monospace;
    font-size: 10pt;
    selection-background-color: #264f78;
    selection-color: #ffffff;
    line-height: 1.25;
}
QToolTip {
    background: #1f2328;
    color: #ffffff;
    border: 1px solid #444c56;
    border-radius: 4px;
    padding: 4px 6px;
}
QLabel#badge {
    background: #eaeef2;
    color: #1f2328;
    border-radius: 4px;
    padding: 2px 8px;
    font-size: 9pt;
}
QLabel#badge_ok { background: #dafbe1; color: #1a7f37; border-radius: 4px; padding: 2px 8px; font-size: 9pt; }
QLabel#badge_warn { background: #fff8c5; color: #9a6700; border-radius: 4px; padding: 2px 8px; font-size: 9pt; }
QLabel#badge_err { background: #ffebe9; color: #cf222e; border-radius: 4px; padding: 2px 8px; font-size: 9pt; }
QFrame#separator { color: #d0d7de; }
"""


# ── 输出区配色规则 ───────────────────────────────────────────────
# Runner._log 按这些 prefix 染色。第一个匹配命中。
# 暗色背景用高饱和度色，亮色背景用柔和色。这里用 GitHub Dark 调色板。
PREFIX_COLORS: list[tuple[str, str]] = [
    ("[错误]", "#f85149"),
    ("[异常]", "#f85149"),
    ("[FAIL]", "#f85149"),
    ("[完成]", "#3fb950"),
    ("[OK]", "#3fb950"),
    ("[提示]", "#58a6ff"),
    ("[chain]", "#bc8cff"),
    ("[跳过]", "#d29922"),
    ("[退出]", "#3fb950"),  # 默认绿；[退出] rc!=0 会在 _log 里特判覆盖
]
EXIT_RE = re.compile(r"\[退出\][^\n]*→ (\d+)")


def which_or_none(name: str) -> str | None:
    return shutil.which(name)


def get_version() -> str:
    """从 pyproject.toml / pyproject / git tag 读版本号。失败回退到 'dev'。

    顺序：
      1) pyproject.toml  [project] version = ...
      2) pyproject       [tool.poetry] version = ...
      3) git describe --tags --always --dirty
      4) 'dev'
    """
    candidates = [
        os.path.join(PROJECT_ROOT, "pyproject.toml"),
        os.path.join(PROJECT_ROOT, "pyproject"),
    ]
    for path in candidates:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    m = re.match(r'\s*version\s*=\s*["\']([^"\']+)["\']', line)
                    if m:
                        return m.group(1).lstrip("v")
        except OSError:
            pass
    # git describe
    try:
        out = subprocess.check_output(
            ["git", "describe", "--tags", "--always", "--dirty"],
            cwd=PROJECT_ROOT,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        return out.decode("utf-8", errors="replace").strip().lstrip("v") or "dev"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return "dev"


def get_git_info() -> tuple[str, str]:
    """返回 (branch, short_sha)。失败时 ('''', '?')。git 不可用时 ('?', '?')。"""
    try:
        branch = subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=PROJECT_ROOT,
            stderr=subprocess.DEVNULL,
            timeout=2,
        ).decode("utf-8", errors="replace").strip()
        sha = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=PROJECT_ROOT,
            stderr=subprocess.DEVNULL,
            timeout=2,
        ).decode("utf-8", errors="replace").strip()
        # dirty 标记
        try:
            subprocess.check_output(
                ["git", "diff", "--no-color", "--quiet"],
                cwd=PROJECT_ROOT,
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
            dirty = ""
        except subprocess.CalledProcessError:
            dirty = "*"
        return branch, f"{sha}{dirty}"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return "?", "?"


def detect_toolchain() -> dict:
    """逐个探测 fvm / flutter / dart / cargo 在不在 PATH 上。

    返回的 dict 里有每个工具的具体路径，缺失则 None。
    mode 字段保留是为了 UI 显示：「全 fvm」「部分缺失」「全缺」。
    """
    fvm = which_or_none("fvm")
    flutter = which_or_none("flutter")
    dart = which_or_none("dart")
    cargo = which_or_none("cargo")

    have = sum(x is not None for x in (fvm, flutter, dart, cargo))
    if have == 4:
        mode = "fvm"  # fvm + 隐含的 flutter/dart/cargo
    elif have == 3 and fvm:
        mode = "fvm-partial"
    elif have >= 1:
        mode = "partial"
    else:
        mode = "missing"

    return {
        "mode": mode,
        "fvm": fvm,
        "flutter": flutter,
        "dart": dart,
        "cargo": cargo,
    }


def flutter_cmd(toolchain: dict, *args: str) -> list[str]:
    if toolchain["fvm"] is not None:
        return ["fvm", "flutter", *args]
    if toolchain["flutter"] is not None:
        return ["flutter", *args]
    raise FileNotFoundError("找不到 flutter（也没装 fvm）")


def dart_cmd(toolchain: dict, *args: str) -> list[str]:
    if toolchain["fvm"] is not None:
        return ["fvm", "dart", *args]
    if toolchain["dart"] is not None:
        return ["dart", *args]
    raise FileNotFoundError("找不到 dart（也没装 fvm）")


def cargo_cmd(toolchain: dict, *args: str) -> list[str]:
    if toolchain["cargo"] is not None:
        return ["cargo", *args]
    raise FileNotFoundError("找不到 cargo（rustup 装 ~/.cargo/bin/cargo 并加入 PATH）")


def python_cmd(toolchain: dict, *args: str) -> list[str]:
    # 走 PATH 上的 python3，不强制 fvm；用于 ui.py 自检等纯 Python 任务。
    return ["python3", *args]


# 任务定义: (按钮文字, 类型, 命令, 工作目录, 是否清屏, 依赖的工具)
# 类型: "flutter" / "dart" / "shell" / None
# "shell" 任务会在 system 模式下自动抹掉 `fvm ` 前缀
# "依赖的工具" 用于运行前预检，缺失时直接报错而不是让 bash 报"未找到命令"
TASKS = {
    "pub get": ("flutter", ["pub", "get"], APP_DIR, False, ["flutter"]),
    "codegen (build_runner + slang)": (
        "shell",
        "fvm dart run build_runner build && fvm dart run slang",
        APP_DIR,
        False,
        ["dart"],
    ),
    "PR4 codegen (全量 build_runner + slang, 修 193 个错)": (
        "shell",
        "fvm dart run build_runner build && fvm dart run slang",
        APP_DIR,
        False,
        ["dart"],
    ),
    # NOTE: --build-filter on build_runner is *not* an incremental mode — it
    # sweeps the generated tree and removes anything not matching the
    # filter, so a "sync-only" run wipes settings_provider.mapper.dart,
    # android_channel.mapper.dart, and mocks.mocks.dart. Always run the
    # full codegen above instead. Kept here as a trap detector.
    "PR3/4 增量 codegen (slang + sync mapper) [废弃: filter 会清其他 mapper]": (
        "shell",
        "fvm dart run slang && fvm dart run build_runner build --build-filter 'lib/model/persistence/sync_share.mapper.dart' "
        "--build-filter 'lib/provider/sync/sync_session.mapper.dart'",
        APP_DIR,
        False,
        ["dart"],
    ),
    "build_runner 只生成 sync mapper (PR3 增量) [废弃]": (
        "shell",
        "fvm dart run build_runner build --build-filter 'lib/model/persistence/sync_share.mapper.dart' "
        "--build-filter 'lib/provider/sync/sync_session.mapper.dart'",
        APP_DIR,
        False,
        ["dart"],
    ),
    "slang codegen (PR4 i18n 新字符串)": (
        "shell",
        # 必须先 `fvm flutter pub get` 解析 pub workspace（localsend_isolates
        # 依赖 Flutter SDK，纯 `dart pub` 解不出来）
        "fvm flutter pub get && fvm dart run slang",
        APP_DIR,
        False,
        ["flutter", "dart"],
    ),
    "PR5 flutter analyze (browse_*.dart + receive_tab 增量)": (
        "shell",
        "fvm flutter analyze "
        "lib/pages/browse_shares_page.dart "
        "lib/pages/browse_share_tree_page.dart "
        "lib/pages/tabs/receive_tab.dart "
        "lib/provider/sync "
        "lib/model/persistence/sync_share.dart",
        APP_DIR,
        False,
        ["flutter"],
    ),
    # chain 任务：args 是其他 task 的 label list（main() 端从 TASKS 查表展开）。
    # 串行跑，前一个 rc != 0 就停。适合「一键验证」场景。
    "PR5 全套验证 (chain: slang + analyze + test)": (
        "chain",
        [
            "slang codegen (PR4 i18n 新字符串)",
            "PR5 flutter analyze (browse_*.dart + receive_tab 增量)",
            "flutter test",
        ],
        APP_DIR,
        False,
        ["dart", "flutter"],
    ),
    "PR6 flutter analyze (sync_session_* + dialog 增量)": (
        "shell",
        # PR 6 增量：只分析新加的 sync session 文件，避免全量 analyze 的 30s+ 编译
        # 包含 state / provider / page / dialog / plan_response / browse_share_tree
        "fvm flutter analyze "
        "lib/provider/sync/plan_response.dart "
        "lib/provider/sync/sync_session_state.dart "
        "lib/provider/sync/sync_session_provider.dart "
        "lib/pages/sync_session_page.dart "
        "lib/pages/dialogs/sync_conflict_dialog.dart "
        "lib/pages/browse_share_tree_page.dart",
        APP_DIR,
        False,
        ["flutter"],
    ),
    "PR6 全套验证 (chain: slang + PR6 analyze + flutter test)": (
        "chain",
        [
            "slang codegen (PR4 i18n 新字符串)",
            "PR6 flutter analyze (sync_session_* + dialog 增量)",
            "flutter test",
        ],
        APP_DIR,
        False,
        ["dart", "flutter"],
    ),
    "flutter analyze (仅 sync 文件, PR3 增量)": (
        "shell",
        "fvm flutter analyze lib/provider/sync lib/model/persistence/sync_share.dart",
        APP_DIR,
        False,
        ["flutter"],
    ),
    "ui.py 自检 (--dry-run, 不弹窗不跑命令)": (
        "python",
        ["ui.py", "--dry-run"],
        PROJECT_ROOT,
        False,
        ["python3"],
    ),
    # 代理测试：跑 4 个 curl 看 7890 端口 + pub.dev / storage.googleapis.com / crates.io 通不通。
    # --max-time 8：挂超时立即返回（代理死了不会一直卡）。
    # 每个 curl 独立打印 status + 用时，方便定位是代理挂还是目标挂。
    # 即使 ui.py 顶栏「代理」没勾，curl 也会显式带 -x 走 7890，所以这条命令永远走代理。
    "代理测试 (curl pub.dev / storage / crates.io via 127.0.0.1:7890)": (
        "shell",
        # -sIL：silent + follow redirect + HEAD。-o /dev/null：不输出 body。
        # -w '%{http_code} ...'：打印 status code + 用时。
        "echo '=== 1. 代理 7890 本身通不通 ===' && "
        "curl -sI --max-time 5 -x http://127.0.0.1:7890 https://www.google.com -o /dev/null -w 'http://127.0.0.1:7890 -> %{http_code} (time=%{time_total}s)\\n' || echo '[FAIL] 代理 7890 不通' ; "
        "echo '=== 2. pub.dev (Dart 包) ===' && "
        "curl -sIL --max-time 8 -x http://127.0.0.1:7890 https://pub.dev/ -o /dev/null -w 'pub.dev -> %{http_code}\\n' || echo '[FAIL] pub.dev 走不通' ; "
        "echo '=== 3. storage.googleapis.com (Flutter engine 镜像) ===' && "
        "curl -sIL --max-time 8 -x http://127.0.0.1:7890 https://storage.googleapis.com/ -o /dev/null -w 'storage -> %{http_code}\\n' || echo '[FAIL] storage.googleapis.com 走不通' ; "
        "echo '=== 4. crates.io (cargo 依赖) ===' && "
        "curl -sIL --max-time 8 -x http://127.0.0.1:7890 https://crates.io/ -o /dev/null -w 'crates.io -> %{http_code}\\n' || echo '[FAIL] crates.io 走不通'",
        PROJECT_ROOT,
        False,
        [],
    ),
    "format 检查 (150 列)": (
        "dart",
        ["format", "--set-exit-if-changed", "lib", "test"],
        APP_DIR,
        False,
        ["dart"],
    ),
    "flutter analyze": ("flutter", ["analyze"], APP_DIR, False, ["flutter"]),
    "flutter test": ("flutter", ["test"], APP_DIR, False, ["flutter"]),
    "全部检查 (format + analyze + test)": (
        "shell",
        "fvm dart format --set-exit-if-changed lib test && fvm flutter analyze && fvm flutter test",
        APP_DIR,
        False,
        ["dart", "flutter"],
    ),
    "rust: cargo test --features full": (
        None,
        ["cargo", "test", "--features", "full"],
        CORE_DIR,
        False,
        ["cargo"],
    ),
    "rust: cargo test --lib sync (PR1+PR2 单元测试)": (
        None,
        ["cargo", "test", "--features", "full", "--lib", "sync"],
        CORE_DIR,
        False,
        ["cargo"],
    ),
    "rust: cargo clippy --features full": (
        None,
        ["cargo", "clippy", "--features", "full", "--all-targets", "--", "-D", "warnings"],
        CORE_DIR,
        False,
        ["cargo"],
    ),
    "rust: cargo clippy sync (仅 PR1+PR2 范围, 验证 0 warning)": (
        "shell",
        # 只看 sync 模块的 clippy 警告，过滤掉 pre-existing 噪音
        "cargo clippy --features full --lib --tests -p localsend -- "
        "-D warnings 2>&1 | "
        "awk '/^warning:|^error:/ { print; } "
        "/--> / { if (prev) print prev \" -> \" $0; prev = $0; }' | "
        "grep -E 'sync/(mod|manifest|diff|state|http)\\.rs' || "
        "echo '[完成] sync 模块无 clippy warning'",
        CORE_DIR,
        False,
        ["cargo"],
    ),
    "rust: cargo test --features full --test sync_server (端点集成测试)": (
        None,
        ["cargo", "test", "--features", "full", "--test", "sync_server"],
        CORE_DIR,
        False,
        ["cargo"],
    ),
    "rust: cargo check (isolates)": (
        None,
        ["cargo", "check"],
        RUST_ISOLATES_DIR,
        False,
        ["cargo"],
    ),
    "flutter run (会阻塞)": ("flutter_run", ["run"], APP_DIR, False, ["flutter"]),
    # ----- 一键下载 / 一键编译 -----
    "一键下载 (pub + cargo)": (
        "shell",
        "fvm flutter pub get && cargo fetch",
        PROJECT_ROOT,
        False,
        ["flutter", "cargo"],
    ),
    "一键编译 Linux (release)": (
        "flutter",
        ["build", "linux", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    "清 flutter build 缓存 (rm -rf app/build, 解决 install /usr/local 报错)": (
        "shell",
        # CMakeCache.txt 里的 CMAKE_INSTALL_PREFIX 一旦写死就回不去
        # 删 app/build/ 让 CMakeLists.txt 第 99-101 行的 if(INITIALIZED_TO_DEFAULT) 重新触发
        # 然后 install 会自动落到 build/linux/x64/debug/bundle/，根本不写 /usr/local
        "rm -rf /home/bv/code/localsend/app/build; "
        "echo '[完成] 删了 app/build/，下次点 flutter run 会重新 cmake configure'; "
        "echo '[提示] app/build 没了，flutter run 会重新编译（5-15 分钟）'",
        PROJECT_ROOT,
        False,
        [],
    ),
    "flutter run (装到 ~/.local, 不写 /usr/local)": (
        "shell",
        # 默认 CMake install prefix 是 /usr/local，没 sudo 写不进去
        # 改成 $HOME/.local 让 build/install 都不需要 root
        "export CMAKE_INSTALL_PREFIX=\"$HOME/.local/localsend\"; "
        "mkdir -p \"$CMAKE_INSTALL_PREFIX\"; "
        "echo \"[提示] install prefix: $CMAKE_INSTALL_PREFIX\"; "
        "fvm flutter run -d linux",
        APP_DIR,
        False,
        ["flutter"],
    ),
    "sudo 一次 /usr/local (修权限后跑 flutter run)": (
        "shell",
        # /usr/local 给当前用户写权限
        "sudo chown -R $USER /usr/local 2>&1 || sudo chmod -R u+w /usr/local 2>&1; "
        "echo '权限已改，可以点 flutter run (会阻塞)'",
        PROJECT_ROOT,
        False,
        ["sudo"],
    ),
    "一键编译 Android APK": (
        "flutter",
        ["build", "apk", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    "一键编译 Android AppBundle": (
        "flutter",
        ["build", "appbundle", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    "一键编译 macOS (release)": (
        "flutter",
        ["build", "macos", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    "一键编译 Windows (release)": (
        "flutter",
        ["build", "windows", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    # ----- 打包给其他人用 (Package) -----
    # 区别于「编译 (Build)」：编译只出中间产物 (apk/ipa/dmg 还没装好 / app/ 目录没压成 AppImage)，
    # 这里是「拿到可以发朋友的成品」流程。
    #
    # Android APK 已经可以直接发，所以「打 APK 到桌面」= build + cp 一步到位。
    # iOS / macOS / Windows 的「打包」步骤需要原生工具（xcodebuild / hdiutil / Inno Setup），
    # 因此 shell 命令里有环境依赖警告；当前 Linux 主机只能跑 Linux AppImage / deb / CLI。

    # APK 已经签名（debug.keystore）后即可分发，朋友开「未知来源」装上就能用。
    # 产物路径：app/build/app/outputs/flutter-apk/app-release.apk
    # 拷到桌面后双击 .apk → 安卓安装器（macOS 弹「未知开发者」先去系统设置允许）。
    "打 Android APK 到桌面 (build apk + cp ~/Desktop/LocalSend.apk)": (
        "shell",
        "fvm flutter build apk --release && "
        "mkdir -p ~/Desktop && "
        "cp app/build/app/outputs/flutter-apk/app-release.apk ~/Desktop/LocalSend.apk && "
        "ls -lh ~/Desktop/LocalSend.apk && "
        "echo '\\n[完成] APK 已放到桌面：~/Desktop/LocalSend.apk\\n' && "
        "echo '发朋友：微信传文件 / 网盘 / U 盘均可。朋友手机需要开「未知来源」权限。'",
        PROJECT_ROOT,
        False,
        ["flutter"],
    ),

    # Linux AppImage：单文件双击就跑，最适合发给 Linux 朋友。
    # 流程（来自 support/scripts/compile_linux_appimage.sh，但去掉 /tmp 复制）：
    #   1) flutter build linux --release   → build/linux/x64/release/bundle/
    #   2) 复制 bundle/* 到 AppDir/         → appimage-builder 的工作目录
    #   3) 复制 AppImageBuilder_x86_64.yml → AppImageBuilder.yml
    #   4) 部署图标 localsend.png + 写 .desktop（appimage-builder 不会自动生成）
    #   5) appimage-builder                → 生成 LocalSend-x86_64.AppImage
    # 前置：appimage-builder 装到 /usr/local/bin/（参考 support/scripts/compile_linux_appimage.sh 头注释）
    # 产物路径：LocalSend-x86_64.AppImage（项目根目录）
    "打 Linux AppImage (build + appimage-builder)": (
        "shell",
        "cd app && fvm flutter build linux --release && cd .. && "
        # ---- 增量构建：只清产物，保留 appimage-build/.apt_cache/ ----
        # appimage-builder 的 apt 包缓存在 appimage-build/.apt_cache/，
        # 全删会让下次重新 apt-get 几十 MB。
        "rm -rf AppDir LocalSend-*.AppImage AppDir.tar.gz .appimage-builder.cache && "
        "rm -rf appimage-build/AppDir appimage-build/*.AppImage 2>/dev/null; "
        "mkdir -p AppDir && "
        "cp -r app/build/linux/x64/release/bundle/* AppDir/ && "
        "cp support/build/appimage/AppImageBuilder_x86_64.yml AppImageBuilder.yml && "
        # ---- 图标部署：appimage-builder 找 AppDir/usr/share/icons/hicolor/<size>x<size>/apps/localsend.png ----
        "ICON_SRC=app/build/linux/x64/release/bundle/data/flutter_assets/assets/img/logo-512.png && "
        "if [ -f \"$ICON_SRC\" ]; then "
        "  for SIZE in 512 256 128 32; do "
        "    DEST=\"AppDir/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps/localsend.png\"; "
        "    mkdir -p \"$(dirname \"$DEST\")\"; "
        "    cp \"$ICON_SRC\" \"$DEST\"; "
        "  done; "
        "  mkdir -p AppDir/usr/share/pixmaps; "
        "  cp \"$ICON_SRC\" AppDir/usr/share/pixmaps/localsend.png; "
        "  echo '[图标] 已部署 4 套 hicolor 图标 + pixmap 兜底'; "
        "else "
        "  echo '[警告] 未找到 $ICON_SRC，AppImage 启动后可能无图标'; "
        "fi && "
        # ---- .desktop 文件：appimage-builder 不会自动生成，没有它桌面启动器找不到应用 ----
        # 用 printf 替代 heredoc，避免嵌套在 bash -c 里时某些 shell 的转义问题。
        "printf '%s\\n' '[Desktop Entry]' 'Type=Application' 'Name=LocalSend' "
        "'GenericName=File Transfer' 'Comment=Share files to nearby devices' "
        "'Categories=Network;FileTransfer;Utility;' 'Exec=localsend_app %U' "
        "'Icon=localsend' 'Terminal=false' 'StartupNotify=true' "
        "'StartupWMClass=localsend_app' > AppDir/org.localsend.localsend_app.desktop && "
        "mkdir -p AppDir/usr/share/applications && "
        "cp AppDir/org.localsend.localsend_app.desktop AppDir/usr/share/applications/org.localsend.localsend_app.desktop && "
        "chmod +x AppDir/org.localsend.localsend_app.desktop AppDir/usr/share/applications/org.localsend.localsend_app.desktop && "
        "echo '[.desktop] 已写入 AppDir/ 与 usr/share/applications/' && "
        # ---- 探测 appimage-builder ----
        "APPIMAGE_BUILDER=$(command -v appimage-builder 2>/dev/null || "
        "ls -1 /usr/local/bin/appimage-builder ~/.local/bin/appimage-builder "
        "/home/bv/code/localsend/.tools/appimage-builder 2>/dev/null | head -1) && "
        "if [ -z \"$APPIMAGE_BUILDER\" ] || [ ! -x \"$APPIMAGE_BUILDER\" ]; then "
        "echo '[错误] appimage-builder 未安装或不可执行。跑：'; "
        "echo '       python3 install-appimage-builder.py'; exit 1; "
        "fi && "
        "echo \"[使用] $APPIMAGE_BUILDER\" && "
        "\"$APPIMAGE_BUILDER\" --recipe AppImageBuilder.yml && "
        "chmod +x LocalSend-*-x86_64.AppImage && "
        "echo '\\n[完成] AppImage 产物：' && "
        "ls -lh LocalSend-*.AppImage",
        PROJECT_ROOT,
        False,
        ["flutter"],
    ),

    # Linux .deb：Debian/Ubuntu 系统包，apt install ./localsend.deb 一行命令。
    # 流程：
    #   1) flutter build linux --release
    #   2) 用 support/linux/packaging/deb/make_config.yaml + make_*.sh 生成 .deb
    # 注：原仓库没现成 make_deb.sh，需要按 AppImageBuilder 流程自行 dpkg-deb --build，
    # 这里先留个 stub —— 完整 .deb 打包超出本按钮范围，请参考 app/linux/packaging/deb/make_config.yaml。
    "打 Linux deb (build + dpkg-deb, 需自行补 make_deb.sh) [WIP]": (
        "shell",
        "echo '[TODO] deb 打包流程：' && "
        "echo '  1) cd app && fvm flutter build linux --release' && "
        "echo '  2) dpkg-deb --build app/build/linux/x64/release/bundle localsend_$(cat app/pubspec.yaml | grep ^version: | awk \"{print \\$2}\" | tr -d \"\\\"\")_amd64.deb' && "
        "echo '  3) ls -lh localsend_*.deb' && "
        "echo '' && "
        "echo '完整 yaml 在 app/linux/packaging/deb/make_config.yaml，可以写 make_deb.sh 自动化。'",
        PROJECT_ROOT,
        False,
        ["flutter"],
    ),

    # CLI release：单二进制 ~10MB，丢服务器跑 cron 或塞 Docker 镜像。
    # 产物路径：cli/target/release/localsend
    # 注意 cargo build --release 走 crates.io，国内需要代理。
    "打 CLI release (cargo build --release)": (
        "cargo",
        ["build", "--release", "--manifest-path", os.path.join(PROJECT_ROOT, "cli", "Cargo.toml")],
        PROJECT_ROOT,
        False,
        ["cargo"],
    ),

    # iOS IPA：需 macOS + Apple Developer 账号 + Xcode。
    # 当前 Linux 跑不了，按钮可点但会失败（错误信息清楚）。
    "打 iOS IPA (flutter build ipa, 需 macOS)": (
        "flutter",
        ["build", "ipa", "--release"],
        APP_DIR,
        False,
        ["flutter"],
    ),

    # macOS DMG：需 macOS + Xcode（hdiutil 打 dmg）。
    # 当前 Linux 跑不了。
    "打 macOS DMG (build + compile_mac_dmg.sh, 需 macOS)": (
        "shell",
        "fvm flutter build macos --release && "
        "bash support/scripts/compile_mac_dmg.sh && "
        "ls -lh build/macos/Product/LocalSend-*.dmg 2>/dev/null || ls -lh LocalSend-*.dmg 2>/dev/null",
        APP_DIR,
        False,
        ["flutter"],
    ),

    # Windows Setup.exe：需 Windows + Inno Setup 6（ISCC.exe）。
    # 流程：flutter build windows → ISCC.exe compile_windows_exe-inno.iss → LocalSend-Setup-*.exe
    "打 Windows Setup.exe (build + Inno Setup, 需 Windows)": (
        "shell",
        "flutter build windows --release && "
        "\"C:\\\\Program Files (x86)\\\\Inno Setup 6\\\\ISCC.exe\" /Qp support/scripts/compile_windows_exe-inno.iss && "
        "ls -lh LocalSend-Setup-*.exe",
        APP_DIR,
        False,
        ["flutter"],
    ),

    # 一站式：编译所有能在这台机器上跑的产物（Android APK + Linux bundle + Linux AppImage + CLI）。
    # chain 任务：前一个 rc != 0 停。CI 触发 release 时用。
    "打包全流程 (chain: APK + Linux AppImage + CLI)": (
        "chain",
        [
            "打 Android APK 到桌面 (build apk + cp ~/Desktop/LocalSend.apk)",
            "打 Linux AppImage (build + appimage-builder)",
            "打 CLI release (cargo build --release)",
        ],
        PROJECT_ROOT,
        False,
        ["flutter", "cargo"],
    ),
    "安装 cargo (rustup, 走代理)": (
        "shell",
        # 幂等：装了就跳过，否则用 rustup 官方脚本装 stable + minimal profile
        "if command -v cargo >/dev/null 2>&1; then "
        "echo '[跳过] cargo 已经在 PATH 上: '$(command -v cargo); "
        "cargo --version; "
        "else "
        "echo '[安装] 下载 rustup-init 并安装 cargo (stable, minimal)...'; "
        "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal; "
        "echo '[完成] cargo 在 ~/.cargo/bin/cargo'; "
        "echo '[提示] 下次点 cargo 按钮 GUI 会自动把 ~/.cargo/bin 加到 PATH，不用重启'; "
        "fi",
        PROJECT_ROOT,
        False,
        ["curl"],
    ),
    "安装 Linux 编译依赖 (apt, pkexec)": (
        "shell",
        # 图形 sudo 框；缺哪个装哪个；幂等
        # 包含：CMake/编译器基础 + Flutter Linux 桌面 + tray_manager + 通知 + keyring
        "echo '[检查] 当前已装的编译依赖...'; "
        "for pkg in clang cmake ninja-build g++ pkg-config libgtk-3-dev "
        "libayatana-appindicator3-dev libnotify-dev libsecret-1-dev libjsoncpp-dev; do "
        "if dpkg -s \"$pkg\" >/dev/null 2>&1; then echo \"  ✓ $pkg\"; "
        "else echo \"  ✗ $pkg (将装)\"; MISSING=\"$MISSING $pkg\"; fi; "
        "done; "
        "if [ -z \"$MISSING\" ]; then "
        "echo '[跳过] 所有依赖已装'; "
        "else "
        "echo '[安装] 走 pkexec 弹图形密码框...'; "
        "pkexec apt-get install -y $MISSING; "
        "fi",
        PROJECT_ROOT,
        False,
        ["pkexec", "apt-get"],
    ),
    "解锁 flutter 启动锁 (杀卡住的进程+删 .lock)": (
        "shell",
        # flutter 工具启动时会在 $FLUTTER_ROOT/bin/cache/.lock 放一个文件锁
        # 卡死的 flutter run / flutter build 会让这个锁一直留着
        "echo '[解锁] 杀死卡住的 flutter / dart 进程...'; "
        "pkill -9 -f 'flutter_tools' 2>/dev/null && echo '  杀 flutter_tools' || echo '  (没有 flutter_tools 进程)'; "
        "pkill -9 -f 'frontend_server' 2>/dev/null && echo '  杀 frontend_server' || echo '  (没有 frontend_server 进程)'; "
        "pkill -9 -f 'dart bin/flutter' 2>/dev/null; "
        "pkill -9 -f 'flutter run' 2>/dev/null && echo '  杀 flutter run' || echo '  (没有 flutter run 进程)'; "
        "echo '[解锁] 删 SDK cache/.lock...'; "
        "FLUTTER_BIN=$(command -v flutter 2>/dev/null); "
        "if [ -n \"$FLUTTER_BIN\" ]; then "
        "  LOCK_DIR=$(dirname \"$FLUTTER_BIN\"); "
        "  LOCK=\"$LOCK_DIR/cache/.lock\"; "
        "  if [ -f \"$LOCK\" ]; then rm -f \"$LOCK\" && echo \"  删 $LOCK\"; else echo \"  (无 $LOCK)\"; fi; "
        "else echo '  (找不到 flutter，跳过)'; fi; "
        "echo '[提示] 再跑一次 pub get 或 flutter run 试试'",
        PROJECT_ROOT,
        False,
        ["pkill"],
    ),
    "pub get (verbose, 看下载进度)": (
        "flutter",
        ["pub", "get", "--verbose"],
        APP_DIR,
        False,
        ["flutter"],
    ),
    "cargo 镜像源 (写到 ~/.cargo/config.toml, 清华)": (
        "shell",
        # 国内 cargo 拉 crates.io 经常被代理坑或 TLS 挂，写死镜像最稳
        # 幂等：先备份已有 config.toml，再覆盖写
        "mkdir -p ~/.cargo && "
        "if [ -f ~/.cargo/config.toml ]; then "
        "cp -v ~/.cargo/config.toml ~/.cargo/config.toml.bak.$(date +%Y%m%d%H%M%S); "
        "fi && "
        "cat > ~/.cargo/config.toml <<'EOF'\n"
        "[source.crates-io]\n"
        "replace-with = \"tuna\"\n"
        "\n"
        "[source.tuna]\n"
        "registry = \"sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-sparse/\"\n"
        "EOF\n"
        "echo '--- ~/.cargo/config.toml ---'; "
        "cat ~/.cargo/config.toml; "
        "echo; echo '---'; "
        "echo '[提示] git 依赖仍走原 URL，需要代理请配：'; "
        "echo '  git config --global http.proxy http://127.0.0.1:7890'; "
        "echo '[撤销] 删 ~/.cargo/config.toml 恢复 crates.io'",
        PROJECT_ROOT,
        False,
        [],
    ),
    "诊断 + 修 git 代理 (socks5→http, cargo 才会认)": (
        "shell",
        # cargo 不认 socks5 proxy，只认 HTTP 代理。git 设了 socks5 会让 cargo 挂掉
        # 把 socks5://127.0.0.1:7890 改成 http://127.0.0.1:7890（clash/v2ray 都接受 HTTP CONNECT）
        "echo '=== 改前 ==='; "
        "git config --global --get-regexp 'http.*proxy' || echo '(无)'; "
        "echo; "
        "for k in http.proxy https.proxy; do "
        "v=$(git config --global --get $k 2>/dev/null); "
        "if [ -n \"$v\" ]; then "
        "if echo \"$v\" | grep -q '^socks5'; then "
        "new=$(echo \"$v\" | sed 's|^socks5h\\?://|http://|'); "
        "git config --global $k \"$new\"; "
        "echo \"  $k: $v  ->  $new\"; "
        "else echo \"  $k: $v (非 socks5，跳过)\"; fi; "
        "fi; "
        "done; "
        "echo; echo '=== 改后 ==='; "
        "git config --global --get-regexp 'http.*proxy' || echo '(无)'; "
        "echo; echo '=== 现在跑一下 cargo fetch 试水 ==='; "
        "timeout 30 cargo fetch --manifest-path /home/bv/code/localsend/cli/Cargo.toml 2>&1 | tail -8",
        PROJECT_ROOT,
        False,
        ["git", "cargo"],
    ),
    "预下载 (cargo fetch, 不编译)": (
        "cargo",
        ["fetch", "--locked"],
        PROJECT_ROOT,
        False,
        ["cargo"],
    ),
    "cargo build --offline (完全离线编译)": (
        "shell",
        # 缓存里有就完全离线编，没有的会报 "no matching package"
        # 适合：网络挂了 + 已经 fetch 过
        "cargo build --offline 2>&1 | tail -20",
        PROJECT_ROOT,
        False,
        ["cargo"],
    ),
    "降级 FRB runtime 到 2.12.x (修 codegen 2.12 vs runtime 2.13 不匹配)": (
        "shell",
        # flutter run 报错:
        #   rust_lib_localsend_app's codegen version (2.12.0) should be the same as
        #   runtime version (2.13.0)
        # 根因: 上游 flutter_rust_bridge_codegen (Rust 工具) 只发到 2.12.0，
        #       但 flutter_rust_bridge (Dart 包) 已经 2.13.0
        #       pubspec 写 ^2.12.0 被 caret 升到 2.13.0，sanity check 失败
        # 修法: 把 ^2.12.0 锁成 >=2.12.0 <2.13.0，pub get 后 lock 回到 2.12.x，
        #       与 codegen 2.12.0 对齐
        "set -e; "
        "F=/home/bv/code/localsend/packages/localsend_isolates/pubspec.yaml; "
        "echo '=== [1/4] 改前 ==='; "
        "grep -n 'flutter_rust_bridge' \"$F\"; "
        "echo '=== [2/4] 把 ^2.12.0 改成 >=2.12.0 <2.13.0 ==='; "
        "sed -i 's|flutter_rust_bridge: \\^2.12.0|flutter_rust_bridge: \">=2.12.0 <2.13.0\"|' \"$F\"; "
        "echo '=== [3/4] 改后 ==='; "
        "grep -n 'flutter_rust_bridge' \"$F\"; "
        "cd /home/bv/code/localsend && "
        "echo '=== [4/4] 跑 flutter pub get (lock 会被重新解析到 2.12.x) ==='; "
        "fvm flutter pub get; "
        "echo; "
        "echo '--- 验证 lock 实际版本 ---'; "
        "grep -A 6 '^  flutter_rust_bridge:$' /home/bv/code/localsend/pubspec.lock; "
        "echo; "
        "echo '[完成] runtime 已锁回 2.12.x，可以再点 flutter run'; "
        "echo '[提示] 上游发 2.13.0 的 codegen crate 后，把 pubspec 改回 ^2.12.0 再 pub get 即可'",
        PROJECT_ROOT,
        False,
        ["flutter"],
    ),
    "一键全流程 (下载+分析+Linux 编译)": (
        "shell",
        "fvm flutter pub get && "
        "fvm dart format --set-exit-if-changed lib test && "
        "fvm flutter analyze && "
        "fvm flutter build linux --release",
        APP_DIR,
        False,
        ["flutter", "dart"],
    ),
    "清屏": (None, None, None, True, []),
}


# 按钮 tab 分类
# "清屏" 在 TASKS 里但不在 TASK_TABS，会在主窗口顶栏单独放
TASK_TABS: dict[str, list[str]] = {
    "下载 (Download)": [
        "pub get",
        "pub get (verbose, 看下载进度)",
        "一键下载 (pub + cargo)",
        "预下载 (cargo fetch, 不编译)",
        "cargo 镜像源 (写到 ~/.cargo/config.toml, 清华)",
        "诊断 + 修 git 代理 (socks5→http, cargo 才会认)",
    ],
    "诊断 (Diag)": [
        "ui.py 自检 (--dry-run, 不弹窗不跑命令)",
        "代理测试 (curl pub.dev / storage / crates.io via 127.0.0.1:7890)",
        "诊断 + 修 git 代理 (socks5→http, cargo 才会认)",
    ],
    "检查 (Check)": [
        "ui.py 自检 (--dry-run, 不弹窗不跑命令)",
        "代理测试 (curl pub.dev / storage / crates.io via 127.0.0.1:7890)",
        "format 检查 (150 列)",
        "flutter analyze",
        "flutter analyze (仅 sync 文件, PR3 增量)",
        "PR5 flutter analyze (browse_*.dart + receive_tab 增量)",
        "PR5 全套验证 (chain: slang + analyze + test)",
        "PR6 flutter analyze (sync_session_* + dialog 增量)",
        "PR6 全套验证 (chain: slang + PR6 analyze + flutter test)",
        "flutter test",
        "全部检查 (format + analyze + test)",
        "codegen (build_runner + slang)",
        "slang codegen (PR4 i18n 新字符串)",
        "PR4 codegen (全量 build_runner + slang, 修 193 个错)",
        "PR3/4 增量 codegen (slang + sync mapper) [废弃: filter 会清其他 mapper]",
        "build_runner 只生成 sync mapper (PR3 增量) [废弃]",
        "rust: cargo test --features full",
        "rust: cargo test --lib sync (PR1+PR2 单元测试)",
        "rust: cargo test --features full --test sync_server (端点集成测试)",
        "rust: cargo clippy --features full",
        "rust: cargo clippy sync (仅 PR1+PR2 范围, 验证 0 warning)",
        "rust: cargo check (isolates)",
    ],
    "编译 (Build)": [
        "一键编译 Linux (release)",
        "一键编译 Android APK",
        "一键编译 Android AppBundle",
        "一键编译 macOS (release)",
        "一键编译 Windows (release)",
        "cargo build --offline (完全离线编译)",
        "一键全流程 (下载+分析+Linux 编译)",
        "降级 FRB runtime 到 2.12.x (修 codegen 2.12 vs runtime 2.13 不匹配)",
        "清 flutter build 缓存 (rm -rf app/build, 解决 install /usr/local 报错)",
        "sudo 一次 /usr/local (修权限后跑 flutter run)",
    ],
    "打包 (Package)": [
        "打包全流程 (chain: APK + Linux AppImage + CLI)",
        "打 Android APK 到桌面 (build apk + cp ~/Desktop/LocalSend.apk)",
        "打 Linux AppImage (build + appimage-builder)",
        "打 Linux deb (build + dpkg-deb, 需自行补 make_deb.sh) [WIP]",
        "打 CLI release (cargo build --release)",
        "打 iOS IPA (flutter build ipa, 需 macOS)",
        "打 macOS DMG (build + compile_mac_dmg.sh, 需 macOS)",
        "打 Windows Setup.exe (build + Inno Setup, 需 Windows)",
    ],
    "运行 (Run)": [
        "flutter run (会阻塞)",
        "flutter run (装到 ~/.local, 不写 /usr/local)",
    ],
    "工具链 (Toolchain)": [
        "安装 cargo (rustup, 走代理)",
        "安装 Linux 编译依赖 (apt, pkexec)",
        "解锁 flutter 启动锁 (杀卡住的进程+删 .lock)",
    ],
}

# 启动时检查：tab 里的 label 必须都在 TASKS 里（拼写错就早死）
_TABBED = {l for ls in TASK_TABS.values() for l in ls}
_MISSING = _TABBED - set(TASKS.keys())
assert not _MISSING, f"TASK_TABS 里的 label 不在 TASKS: {_MISSING}"


def build_cmd(toolchain: dict, kind, args, cwd, device_getter=None) -> list[str]:
    """把任务定义里的 (kind, args) 翻译成实际命令列表。"""
    if kind is None:
        # 清屏占位符：Runner 实际上短路了不会调到这里，但返回空列表
        # 让 dry-run 验证时语义清晰。
        return []
    if kind == "shell":
        # shell 任务里硬编码了 fvm，按 fvm 是否安装决定是否保留前缀
        shell_cmd: str = args
        if toolchain["fvm"] is None:
            shell_cmd = shell_cmd.replace("fvm ", "")
        return ["bash", "-c", shell_cmd]
    if kind == "flutter":
        return flutter_cmd(toolchain, *args)
    if kind == "dart":
        return dart_cmd(toolchain, *args)
    if kind == "flutter_run":
        # 动态注入 -d <device>，跳过交互式设备选择器
        device = (device_getter() if device_getter else "linux") or "linux"
        return flutter_cmd(toolchain, *args, "-d", device)
    if kind == "cargo":
        return cargo_cmd(toolchain, *args)
    if kind == "python":
        return python_cmd(toolchain, *args)
    if kind == "chain":
        # marker: submit 看到 kind=="chain" 时切到 _chain_task，不会真调 Popen
        # 返回空 list 让 dry-run 4b 校验不抛 ValueError
        return []
    raise ValueError(f"未知任务类型: {kind}")


def format_cmd_for_display(cmd: list[str]) -> str:
    """让 shell 命令在文本框里显示得更清楚。

    ['bash', '-c', 'fvm flutter pub get && cargo fetch']
    → bash -c 'fvm flutter pub get && cargo fetch'
    """
    if len(cmd) >= 3 and cmd[0] == "bash" and cmd[1] == "-c":
        return f"bash -c '{cmd[2]}'"
    return " ".join(cmd)


class ProxyConfig:
    """代理设置：勾选 + URL + NO_PROXY 列表。

    URL 同时写入 HTTP_PROXY/HTTPS_PROXY/http_proxy/https_proxy 四个变量
    （部分老工具只认小写，如 cargo 的 http 客户端；Go 系只认大写）。
    NO_PROXY 默认排除本机，避免回环打到代理本身。
    """

    def __init__(self):
        self.enabled = True
        self.url = "http://127.0.0.1:7890"
        self.no_proxy = "localhost,127.0.0.1,::1"

    def apply_to_env(self, env: dict) -> dict:
        if not self.enabled:
            return env
        url = self.url.strip()
        no = self.no_proxy.strip()
        if url:
            env["HTTP_PROXY"] = url
            env["HTTPS_PROXY"] = url
            env["http_proxy"] = url
            env["https_proxy"] = url
        if no:
            env["NO_PROXY"] = no
            env["no_proxy"] = no
        return env

    def describe(self) -> str:
        if not self.enabled:
            return "代理: 关"
        url = self.url.strip() or "(空)"
        no = self.no_proxy.strip() or "(空)"
        return f"代理: {url}，NO_PROXY={no}"


class PubMirrorConfig:
    """Dart / Flutter 镜像：国内 pub get 慢时切到 TUNA/SJTU 等。

    留空 = 不设环境变量（走 pub.dev / storage.googleapis.com）。
    设了就走镜像站。注意镜像站只解决 pub.dev 的包，git 依赖仍走原 URL。
    """

    def __init__(self):
        self.pub_url = ""
        self.flutter_url = ""

    def apply_to_env(self, env: dict) -> dict:
        u = self.pub_url.strip()
        if u:
            env["PUB_HOSTED_URL"] = u
        u = self.flutter_url.strip()
        if u:
            env["FLUTTER_STORAGE_BASE_URL"] = u
        return env

    def describe(self) -> str:
        items = []
        u = self.pub_url.strip()
        if u:
            items.append(f"PUB={u}")
        u = self.flutter_url.strip()
        if u:
            items.append(f"FLUTTER={u}")
        return "镜像: " + (", ".join(items) if items else "未启用")


class Runner:
    """子线程跑 subprocess，主线程 QTimer 轮询 self.q 写 QPlainTextEdit。

    跨线程安全：所有 QPlainTextEdit / QStatusBar / QPushButton 写入都发生在主线程
    （_drain_q / _tick_spinner 由 main() 的 QTimer 触发）。子线程只 push 事件到 q。
    """

    def __init__(
        self,
        output: QTextEdit,
        status_bar: QStatusBar,
        status_left: QLabel,
        status_center: QLabel,
        status_right: QLabel,
        buttons_provider,  # callable[[], list[QPushButton]]
        toolchain: dict,
        proxy: ProxyConfig,
        pub_mirror: PubMirrorConfig,
        device_getter=None,
    ):
        self.output = output
        self.status_bar = status_bar
        self.status_left = status_left
        self.status_center = status_center
        self.status_right = status_right
        self._buttons_provider = buttons_provider
        self.toolchain = toolchain
        self.proxy = proxy
        self.pub_mirror = pub_mirror
        self._device_getter = device_getter
        self.q: queue.Queue = queue.Queue()
        self.busy = False
        self.current = ""
        self.started_at = 0.0
        self.last_output_at = 0.0
        self.spinner_state = 0
        self.spinner_chars = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        self.spinner_visible = False
        # 限制文本框最多 10000 行（QTextEdit 没有 setMaximumBlockCount，
        # QPlainTextEdit 有；output 多数情况是 QTextEdit，靠 maxDocLength 软限制）。
        if hasattr(self.output, "setMaximumBlockCount"):
            self.output.setMaximumBlockCount(10000)
        elif hasattr(self.output, "document"):
            doc = self.output.document()
            if hasattr(doc, "setMaximumBlockCount"):
                doc.setMaximumBlockCount(10000)

    def _set_buttons_enabled(self, enabled: bool):
        for b in self._buttons_provider():
            b.setEnabled(enabled)

    def submit(self, name: str, kind, args, cwd, clear: bool, requires: list[str]):
        if self.busy:
            self._log(f"[跳过] 已有任务在跑：{self.current}\n")
            return
        if clear or (kind is None and args is None):
            self.output.clear()
            return

        if kind == "chain":
            # args 已经在 add_button 端从 TASKS 查表展开成 6-tuple list
            # 格式: [(label, sub_kind, sub_args, sub_cwd, sub_clear, sub_requires), ...]
            missing: set[str] = set()
            for _label, _sub_kind, _sub_args, _sub_cwd, _sub_clear, sub_requires in args:
                for r in sub_requires:
                    if which_or_none(r) is None:
                        missing.add(r)
            if missing:
                self._log(f"\n[跳过] chain '{name}' 缺工具：{', '.join(sorted(missing))}\n")
                return
            self._start(name)
            threading.Thread(target=self._chain_task, args=(name, args), daemon=True).start()
            return

        # 预检：列出每个 require，缺失则中止并打清晰错误
        missing = [r for r in requires if which_or_none(r) is None]
        if missing:
            self._log(
                f"\n[跳过] '{name}' 缺少工具：{', '.join(missing)}\n"
                f"        请安装 fvm（https://fvm.app）或把这些加入 PATH。\n"
            )
            return

        try:
            cmd = build_cmd(self.toolchain, kind, args, cwd, self._device_getter)
        except FileNotFoundError as e:
            self._log(f"\n[错误] {e}\n")
            return
        self._start(name)
        threading.Thread(target=self._task, args=(name, cmd, cwd), daemon=True).start()

    def _start(self, name: str):
        """busy / 状态栏 / 按钮 disable，标记任务开始。"""
        self.busy = True
        self.current = name
        self.started_at = time.monotonic()
        self.last_output_at = time.monotonic()
        self._set_buttons_enabled(False)
        self.status_left.setText("运行中")
        self.status_center.setText(f"▶ {name}")
        self.status_center.setStyleSheet("color: #0969da; font-weight: 600;")
        self.status_right.setText(self._format_elapsed())
        self.spinner_visible = False

    def _format_elapsed(self) -> str:
        if self.started_at == 0.0:
            return ""
        elapsed = time.monotonic() - self.started_at
        if elapsed < 60:
            return f"{elapsed:.1f}s"
        m, s = divmod(int(elapsed), 60)
        return f"{m}m{s:02d}s"

    def _chain_task(self, chain_name: str, steps: list[tuple]):
        """串行跑一组任务（每个 step 是 6-tuple）。前一个 rc != 0 就停。
        q.put 用 'line' 事件透传 banner + 输出，用 'done' 事件收尾（让 drain 走现有 set_busy(False)）。"""
        self.q.put(("line", f"\n=== chain: {chain_name} ({len(steps)} 步) ===\n"))
        overall_rc = 0
        for i, (sub_label, sub_kind, sub_args, sub_cwd, _sub_clear, _req) in enumerate(steps, 1):
            self.q.put(("line", f"\n─── [{i}/{len(steps)}] {sub_label} ───\n"))
            try:
                cmd = build_cmd(self.toolchain, sub_kind, sub_args, sub_cwd, self._device_getter)
            except FileNotFoundError as e:
                self.q.put(("line", f"\n[错误] {e}\n"))
                overall_rc = 127
                break
            self.q.put(("line", f"$ {format_cmd_for_display(cmd)}\n  (cwd: {sub_cwd})\n"))
            rc = self._run_sub(sub_label, cmd, sub_cwd)
            self.q.put(("line", f"\n[退出] {sub_label} → {rc}\n"))
            if rc != 0:
                self.q.put(("line", f"\n[chain] 停于 {sub_label} (rc={rc})\n"))
                overall_rc = rc
                break
        if overall_rc == 0:
            self.q.put(("line", f"\n[chain] 全部 {len(steps)} 步通过\n"))
        self.q.put(("done", chain_name, overall_rc))

    def _run_sub(self, name: str, cmd: list[str], cwd: str) -> int:
        """跑一个子命令，q.put("line") 透传，return rc。"""
        env = {**os.environ, "PAGER": "cat", "TERM": "dumb"}
        cargo_bin = os.path.expanduser("~/.cargo/bin")
        if os.path.isdir(cargo_bin):
            env["PATH"] = cargo_bin + os.pathsep + env.get("PATH", "")
        env = self.pub_mirror.apply_to_env(env)
        env = self.proxy.apply_to_env(env)
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=0,
                env=env,
            )
            assert proc.stdout is not None
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                text = chunk.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
                self.q.put(("line", text))
            return proc.wait()
        except FileNotFoundError as e:
            self.q.put(("line", f"\n[错误] 找不到可执行文件：{e}\n"))
            return 127
        except Exception as e:  # noqa: BLE001
            self.q.put(("line", f"\n[异常] {e}\n"))
            return -1

    def _task(self, name, cmd, cwd):
        env = {**os.environ, "PAGER": "cat", "TERM": "dumb"}
        # 自愈：rustup 装的 cargo 在 ~/.cargo/bin，如果当前 shell PATH 里没有就加进去
        cargo_bin = os.path.expanduser("~/.cargo/bin")
        if os.path.isdir(cargo_bin):
            env["PATH"] = cargo_bin + os.pathsep + env.get("PATH", "")
        env = self.pub_mirror.apply_to_env(env)
        env = self.proxy.apply_to_env(env)
        try:
            self.q.put(("start", name, cmd, cwd, self.proxy.describe()))
            # bufsize=0 + 不带 text=True：原始字节流，\r 不会被行缓冲吞掉
            proc = subprocess.Popen(
                cmd,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=0,
                env=env,
            )
            assert proc.stdout is not None
            # 按块读 4 KiB，\r 归一为 \n，UTF-8 错误替换
            # 这样覆盖式进度条（pub get、cargo、rustup 状态行）每一步都能看到
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                text = chunk.decode("utf-8", errors="replace")
                text = text.replace("\r\n", "\n").replace("\r", "\n")
                self.q.put(("line", text))
            rc = proc.wait()
            self.q.put(("done", name, rc))
        except FileNotFoundError as e:
            self.q.put(("line", f"\n[错误] 找不到可执行文件：{e}\n"))
            self.q.put(("done", name, 127))
        except Exception as e:  # noqa: BLE001
            self.q.put(("line", f"\n[异常] {e}\n"))
            self.q.put(("done", name, -1))

    def drain(self):
        """主线程调用：每 50 ms 由 QTimer 触发一次，drain q 里的事件。"""
        try:
            while True:
                item = self.q.get_nowait()
                kind = item[0]
                if kind == "start":
                    _, name, cmd, cwd, proxy_desc = item
                    self._log(f"\n=== {name} ===\n")
                    self._log(f"$ {format_cmd_for_display(cmd)}\n  (cwd: {cwd})\n")
                    self._log(f"  [{proxy_desc}]\n")
                    self._log(f"  [{self.pub_mirror.describe()}]\n")
                    self.last_output_at = time.monotonic()
                    self.spinner_visible = False
                elif kind == "line":
                    self._log(item[1])
                    self.last_output_at = time.monotonic()
                elif kind == "done":
                    _, name, rc = item
                    self._log(f"\n[退出] {name} → {rc}\n")
                    self.busy = False
                    self.current = ""
                    self._set_buttons_enabled(True)
                    self.status_left.setText("就绪")
                    self.status_center.setText("✅ 完成" if rc == 0 else f"❌ 失败 (rc={rc})")
                    self.status_center.setStyleSheet(
                        "color: #1a7f37; font-weight: 600;" if rc == 0
                        else "color: #cf222e; font-weight: 600;"
                    )
                    self.status_right.setText(f"用时 {self._format_elapsed()}")
                    self.spinner_visible = False
                    self.spinner_state = 0
                    self.started_at = 0.0
        except queue.Empty:
            pass

    def tick_spinner(self):
        """主线程调用：每 200 ms 由 QTimer 触发一次，5 秒没新输出就转圈。"""
        if not self.busy:
            return
        idle = time.monotonic() - self.last_output_at
        if idle >= 5.0:
            self.spinner_state = (self.spinner_state + 1) % len(self.spinner_chars)
            ch = self.spinner_chars[self.spinner_state]
            self.status_center.setText(f"▶ {self.current} {ch}")
            self.spinner_visible = True
        # 状态栏右端持续刷新计时
        self.status_right.setText(self._format_elapsed())

    def _log(self, text: str):
        """主线程调用（drain 触发）。prefix 按 PREFIX_COLORS 染色后插入。

        实现：每个 chunk / 整段都重新走 prefix 检测 + 染色 + auto-scroll。
        多次调用的累积文本用同一种 foreground（QTextCursor 不会跨 insert 继承旧 format）。

        智能滚动：用 ensureCursorVisible() —— 它在光标已可见时不动（用户向上看历史
        时不会被强制拉回），光标在 viewport 外时自动滚到光标位置。这样启动时
        welcome banner 完整可见，长任务运行时也能跟随新输出。
        """
        text_clean = text.rstrip("\n")
        if not text_clean:
            return
        # 找 prefix + color
        prefix_color: tuple[str, str] | None = None
        for prefix, color in PREFIX_COLORS:
            if prefix in text_clean:
                prefix_color = (prefix, color)
                break
        # [退出] → 0 绿 / → 1 红（覆盖上面的默认 [退出]=绿）
        if prefix_color and prefix_color[0] == "[退出]":
            m = EXIT_RE.search(text_clean)
            if m:
                rc = m.group(1)
                prefix_color = (m.group(0), "#3fb950" if rc == "0" else "#f85149")
        cursor = self.output.textCursor()
        cursor.movePosition(QTextCursor.End)
        if prefix_color:
            prefix, color = prefix_color
            idx = text_clean.find(prefix)
            before = text_clean[:idx]
            after = text_clean[idx + len(prefix):]
            cursor.insertText(before)
            fmt = QTextCharFormat()
            fmt.setForeground(QColor(color))
            fmt.setFontWeight(QFont.Bold)
            cursor.insertText(prefix, fmt)
            cursor.insertText(after)
        else:
            cursor.insertText(text_clean)
        cursor.insertText("\n")
        # 智能滚动：让光标自动可见（Qt 内置；用户向上看历史时不会被拉回）
        self.output.ensureCursorVisible()


class ProxyDialog(QDialog):
    """代理设置弹窗。返回 (accepted, ProxyConfig) 给调用方决定是否更新外部状态。

    设计：
    - QFormLayout 两列：标签 / 输入
    - 顶部 CheckBox「启用代理」联动下面两个字段的 enabled
    - 「测试代理」按钮：直接调现有的 _proxy_test 逻辑（看 curl 走不走代理）
    - OK / Cancel 按钮
    - 实时校验 URL 格式（空 / http(s)://），错误时禁用 OK
    """

    def __init__(self, proxy: "ProxyConfig", parent=None):
        super().__init__(parent)
        self.setWindowTitle("代理设置")
        self.setModal(True)
        self.setMinimumWidth(480)
        self._initial = proxy  # 引用，方便 reset

        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 12)
        layout.setSpacing(10)

        # 启用代理
        self.enabled_cb = QCheckBox("启用代理（cargo / pub / git 走 HTTP/SOCKS 代理）")
        self.enabled_cb.setChecked(proxy.enabled)
        layout.addWidget(self.enabled_cb)

        # 表单
        form = QFormLayout()
        form.setSpacing(8)
        form.setLabelAlignment(Qt.AlignRight)

        self.url_edit = QLineEdit(proxy.url)
        self.url_edit.setPlaceholderText("http://127.0.0.1:7890")
        form.addRow("URL:", self.url_edit)

        self.noproxy_edit = QLineEdit(proxy.no_proxy)
        self.noproxy_edit.setPlaceholderText("localhost,127.0.0.1,::1")
        form.addRow("NO_PROXY:", self.noproxy_edit)

        # 提示
        hint = QLabel(
            "<span style='color:#57606a;font-size:9pt'>"
            "<b>URL</b> 支持 <code>http://</code>（推荐）/ <code>socks5://</code> / <code>socks5h://</code><br/>"
            "<b>NO_PROXY</b> 逗号分隔，匹配的主机不走代理"
            "</span>"
        )
        hint.setTextFormat(Qt.TextFormat.RichText)
        form.addRow("", hint)
        layout.addLayout(form)

        # 按钮行：测试代理 + OK + Cancel
        btn_row = QHBoxLayout()
        self.test_btn = QPushButton("🔍  测试代理")
        self.test_btn.setToolTip("curl 一下 pub.dev / storage.googleapis.com / crates.io 验证代理可达")
        btn_row.addWidget(self.test_btn)
        btn_row.addStretch(1)
        layout.addLayout(btn_row)

        # OK / Cancel
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("确定")
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

        # 联动：启用 CheckBox 切换时启用/禁用两个输入
        self.enabled_cb.toggled.connect(self.url_edit.setEnabled)
        self.enabled_cb.toggled.connect(self.noproxy_edit.setEnabled)
        self.url_edit.setEnabled(proxy.enabled)
        self.noproxy_edit.setEnabled(proxy.enabled)

        # 实时校验
        self.url_edit.textChanged.connect(self._validate)
        self._validate()

    def _validate(self):
        text = self.url_edit.text().strip()
        ok = True
        if self.enabled_cb.isChecked():
            if not text:
                ok = False
            elif not (text.startswith("http://") or text.startswith("https://")
                      or text.startswith("socks5://") or text.startswith("socks5h://")):
                ok = False
        # 设置 OK 按钮 enabled
        btn = self.findChild(QDialogButtonBox).button(QDialogButtonBox.Ok)
        btn.setEnabled(ok)
        # 视觉反馈
        if ok or not text:
            self.url_edit.setStyleSheet("")
        else:
            self.url_edit.setStyleSheet("border: 1px solid #cf222e;")

    # 在 accept 时回写到外部 ProxyConfig
    def apply_to(self, proxy: "ProxyConfig"):
        proxy.enabled = self.enabled_cb.isChecked()
        proxy.url = self.url_edit.text().strip()
        proxy.no_proxy = self.noproxy_edit.text().strip()


def main(auto_task: str | None = None):
    toolchain = detect_toolchain()
    app = QApplication.instance() or QApplication(sys.argv)
    app.setStyleSheet(QSS)  # 全局 QSS：GitHub Light + 暗色输出区

    win = QMainWindow()
    win.setWindowTitle(f"LocalSend 工具箱 v{get_version()} — {os.path.basename(PROJECT_ROOT)}")
    win.resize(1280, 900)
    win.setMinimumSize(820, 640)

    # 状态栏：分三段（左 = 静态状态 / 中 = 当前任务 + spinner / 右 = 计时器 + 代理提示）
    status_bar = QStatusBar()
    win.setStatusBar(status_bar)
    status_left = QLabel("就绪")
    status_left.setStyleSheet("color: #57606a;")
    status_sep1 = QFrame()
    status_sep1.setFrameShape(QFrame.VLine)
    status_sep1.setFrameShadow(QFrame.Sunken)
    status_center = QLabel("")
    status_center.setStyleSheet("color: #0969da; font-weight: 600;")
    status_sep2 = QFrame()
    status_sep2.setFrameShape(QFrame.VLine)
    status_sep2.setFrameShadow(QFrame.Sunken)
    status_right = QLabel("")
    status_right.setStyleSheet("color: #57606a;")
    status_bar.addWidget(status_left, 1)  # stretch=1 占满左侧
    status_bar.addPermanentWidget(status_sep1)
    status_bar.addPermanentWidget(status_center)  # 中间（task 状态）
    status_bar.addPermanentWidget(status_sep2)
    status_bar.addPermanentWidget(status_right)  # 最右

    central = QWidget()
    win.setCentralWidget(central)
    root_layout = QVBoxLayout(central)
    root_layout.setContentsMargins(10, 10, 10, 6)
    root_layout.setSpacing(8)

    # ── 横向分栏：左 = 配置 + 任务，右 = 暗色日志区 ──
    splitter = QSplitter(Qt.Horizontal)
    splitter.setChildrenCollapsible(False)
    splitter.setHandleWidth(1)
    # splitter 拖把样式
    splitter.setStyleSheet(
        "QSplitter::handle { background: #d0d7de; }"
        "QSplitter::handle:hover { background: #0969da; }"
    )

    # 左侧面板：项目信息 + 环境设置 + 任务（垂直堆叠）
    left_panel = QWidget()
    left_layout = QVBoxLayout(left_panel)
    left_layout.setContentsMargins(0, 0, 0, 0)
    left_layout.setSpacing(8)

    # 右侧面板：暗色输出区 + 顶部工具按钮（清空 / 复制 / 滚动到底）
    right_panel = QWidget()
    right_layout = QVBoxLayout(right_panel)
    right_layout.setContentsMargins(0, 0, 0, 0)
    right_layout.setSpacing(4)

    splitter.addWidget(left_panel)
    splitter.addWidget(right_panel)
    # 初始比例：左 55% / 右 45%
    splitter.setStretchFactor(0, 55)
    splitter.setStretchFactor(1, 45)
    # 实际宽度（resize 时按比例分配）
    splitter.setSizes([660, 540])
    root_layout.addWidget(splitter, stretch=1)

    # ── GroupBox 1: 项目信息 ──
    mode = toolchain["mode"]
    if mode == "fvm":
        mode_text, mode_color = "工具链: fvm ✓", "#1a7f37"
        mode_badge_kind = "ok"
    elif mode == "fvm-partial":
        mode_text, mode_color = "工具链: fvm + 系统补充", "#9a6700"
        mode_badge_kind = "warn"
    elif mode == "partial":
        present = [n for n in ("fvm", "flutter", "dart", "cargo") if toolchain[n]]
        absent = [n for n in ("fvm", "flutter", "dart", "cargo") if not toolchain[n]]
        mode_text = f"工具链: 缺 {', '.join(absent)} ⚠"
        mode_color = "#9a6700"
        mode_badge_kind = "warn"
    else:
        mode_text, mode_color = "工具链: 一个都没找到 ✗", "#cf222e"
        mode_badge_kind = "err"

    branch, sha = get_git_info()
    version = get_version()

    proj_group = QGroupBox("📁 项目信息")
    proj_outer = QVBoxLayout(proj_group)
    proj_outer.setSpacing(6)
    # Row 1: badge 行（版本 + 工具链 + git）
    badge_row = QHBoxLayout()
    badge_row.setSpacing(6)

    ver_badge = QLabel(f"v{version}")
    ver_badge.setObjectName("badge")
    badge_row.addWidget(ver_badge)

    tool_badge = QLabel(mode_text.replace("工具链: ", ""))
    tool_badge.setObjectName(f"badge_{mode_badge_kind}")
    badge_row.addWidget(tool_badge)

    if branch != "?":
        git_badge = QLabel(f"⎇ {branch} @ {sha}")
        git_badge.setObjectName("badge")
        git_badge.setToolTip(f"当前 git 分支: {branch}\ncommit: {sha}")
        badge_row.addWidget(git_badge)

    tasks_count = sum(len(labels) for labels in TASK_TABS.values()) + 1  # +1 = 清屏
    count_badge = QLabel(f"共 {tasks_count} 个任务")
    count_badge.setObjectName("badge")
    badge_row.addWidget(count_badge)

    badge_row.addStretch(1)
    proj_outer.addLayout(badge_row)
    # Row 2: 路径（等宽小字）
    path_label = QLabel(
        f"<span style='color:#57606a;font-size:9pt'>"
        f"<b>项目根</b> <code>{PROJECT_ROOT}</code><br/>"
        f"<b>app</b> <code>{APP_DIR}</code></span>"
    )
    # 默认就是 RichText，setText 时带 < 触发富文本解析
    proj_outer.addWidget(path_label)
    # 阻止 GroupBox 垂直方向被父布局拉伸，保留 sizeHint 高度
    proj_group.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Maximum)

    # ── 环境设置 widget（作为 notebook 第一个 tab；项目信息也放顶部）──
    proxy = ProxyConfig()
    pub_mirror = PubMirrorConfig()

    env_tab = QWidget()
    env_layout = QVBoxLayout(env_tab)
    env_layout.setContentsMargins(12, 12, 12, 12)
    env_layout.setSpacing(10)
    env_layout.setAlignment(Qt.AlignTop)
    # 顶部：项目信息
    env_layout.addWidget(proj_group)
    # 中间：环境设置表单
    env_grid = QGridLayout()
    env_grid.setHorizontalSpacing(8)
    env_grid.setVerticalSpacing(8)
    # 列 stretch: 0=标签, 1=input(主), 2=标签, 3=input
    env_grid.setColumnStretch(0, 0)
    env_grid.setColumnStretch(1, 3)
    env_grid.setColumnStretch(2, 0)
    env_grid.setColumnStretch(3, 3)
    env_layout.addLayout(env_grid)

    # 行 0: 代理 — 按钮 + 当前概要
    proxy_label = QLabel("代理:")
    env_grid.addWidget(proxy_label, 0, 0)
    proxy_btn = QPushButton("⚙  设置代理…")
    proxy_btn.setToolTip("点击打开代理设置弹窗")
    env_grid.addWidget(proxy_btn, 0, 1)
    proxy_summary = QLabel("")

    def refresh_proxy_summary():
        if proxy.enabled and proxy.url:
            proxy_summary.setText(f"✓ <b>{proxy.url}</b>  NO_PROXY=<code>{proxy.no_proxy or '(无)'}</code>")
            proxy_summary.setStyleSheet("color: #1a7f37;")
        else:
            proxy_summary.setText("✗ 未启用")
            proxy_summary.setStyleSheet("color: #afb8c1;")
        # 同步底部状态栏
        status_right.setText(proxy.describe() if proxy.enabled else "代理: 关")
    env_grid.addWidget(proxy_summary, 0, 2, 1, 2)

    def open_proxy_dialog():
        dlg = ProxyDialog(proxy, parent=win)
        # 测试代理：复用 _proxy_test 逻辑
        def _on_test():
            from urllib.request import urlopen, Request
            from urllib.error import URLError
            test_urls = ["https://pub.dev/", "https://storage.googleapis.com/", "https://crates.io/"]
            dlg.test_btn.setEnabled(False)
            dlg.test_btn.setText("🔍  测试中…")
            QApplication.processEvents()
            ok = 0
            for u in test_urls:
                try:
                    r = urlopen(Request(u, headers={"User-Agent": "ui.py/1.0"}), timeout=5)
                    if r.status == 200:
                        ok += 1
                except (URLError, OSError) as e:
                    pass
            dlg.test_btn.setEnabled(True)
            dlg.test_btn.setText("🔍  测试代理")
            if ok == len(test_urls):
                dlg.test_btn.setText(f"✅ {ok}/{len(test_urls)} 全通")
                QTimer.singleShot(2000, lambda: dlg.test_btn.setText("🔍  测试代理"))
            elif ok > 0:
                dlg.test_btn.setText(f"⚠ {ok}/{len(test_urls)} 通")
                QTimer.singleShot(2000, lambda: dlg.test_btn.setText("🔍  测试代理"))
            else:
                dlg.test_btn.setText(f"❌ 全失败")
                QTimer.singleShot(2000, lambda: dlg.test_btn.setText("🔍  测试代理"))
        dlg.test_btn.clicked.connect(_on_test)
        if dlg.exec() == QDialog.Accepted:
            dlg.apply_to(proxy)
            refresh_proxy_summary()
    proxy_btn.clicked.connect(open_proxy_dialog)
    refresh_proxy_summary()

    # 行 1: 镜像 pub / flutter
    env_grid.addWidget(QLabel("镜像 pub:"), 1, 0)
    pub_url_edit = QLineEdit(pub_mirror.pub_url)
    pub_url_edit.setPlaceholderText("https://mirrors.tuna.tsinghua.edu.cn/dart-pub/")
    pub_url_edit.textChanged.connect(lambda t: setattr(pub_mirror, "pub_url", t))
    env_grid.addWidget(pub_url_edit, 1, 1)
    env_grid.addWidget(QLabel("flutter:"), 1, 2)
    flutter_url_edit = QLineEdit(pub_mirror.flutter_url)
    flutter_url_edit.setPlaceholderText("https://mirrors.tuna.tsinghua.edu.cn/flutter")
    flutter_url_edit.textChanged.connect(lambda t: setattr(pub_mirror, "flutter_url", t))
    env_grid.addWidget(flutter_url_edit, 1, 3)

    # 行 2: 设备 + 镜像快捷
    env_grid.addWidget(QLabel("设备:"), 2, 0)
    device_edit = QLineEdit("linux")
    device_edit.setFixedWidth(80)
    env_grid.addWidget(device_edit, 2, 1)
    TUNA_PUB = "https://mirrors.tuna.tsinghua.edu.cn/dart-pub/"
    TUNA_FLUTTER = "https://mirrors.tuna.tsinghua.edu.cn/flutter"
    SJTU_PUB = "https://mirror.sjtu.edu.cn/dart-pub/"
    SJTU_FLUTTER = "https://mirror.sjtu.edu.cn/flutter"

    def set_mirror(pub: str, flutter: str):
        pub_url_edit.setText(pub)
        flutter_url_edit.setText(flutter)

    mirror_row = QHBoxLayout()
    mirror_row.setSpacing(6)
    mirror_row.addWidget(QLabel("镜像快捷:"))
    for text, p, f in [
        ("清华 TUNA", TUNA_PUB, TUNA_FLUTTER),
        ("上交 SJTU", SJTU_PUB, SJTU_FLUTTER),
        ("清空", "", ""),
    ]:
        b = QPushButton(text)
        b.setMaximumWidth(90)
        b.clicked.connect(lambda _=False, _p=p, _f=f: set_mirror(_p, _f))
        mirror_row.addWidget(b)
    mirror_row.addStretch(1)
    mirror_container = QWidget()
    mirror_container.setLayout(mirror_row)
    env_grid.addWidget(mirror_container, 2, 2, 1, 2)

    # ── 控制面板（tab 化：环境设置 + 7 个任务 tab）──
    panel_group = QGroupBox("🚀 控制面板")
    panel_layout = QVBoxLayout(panel_group)
    panel_layout.setContentsMargins(8, 8, 8, 8)

    # 顶栏：清屏按钮（左）+ 状态提示（右）
    task_top = QHBoxLayout()
    clear_btn = QPushButton("🗑  清屏")
    clear_btn.setMaximumWidth(90)
    task_top.addWidget(clear_btn)
    task_top.addStretch(1)
    hint_label = QLabel("点按钮跑任务；chain 任务自动串行 · 蓝按钮 = 一键验证")
    hint_label.setStyleSheet("color: #8b949e; font-size: 9pt;")
    task_top.addWidget(hint_label)
    panel_layout.addLayout(task_top)

    # tab 区：每 tab 一组按钮。QScrollArea 让按钮多时可滚。
    notebook = QTabWidget()
    COLS = 1  # 1 列让按钮宽度 = tab 全宽，长文字也能完整显示
    btns: dict[str, QPushButton] = {}

    def attach_button(b: QPushButton, label: str, kind, cmd_args, cwd, clear, requires):
        b.clicked.connect(
            lambda _=False, n=label, k=kind, a=cmd_args, d=cwd, cl=clear, r=requires: runner.submit(n, k, a, d, cl, r)
        )
        btns[label] = b

    def resolve_args(label: str):
        """从 TASKS 查表 + chain 展开，返回 (kind, cmd_args, cwd, clear, requires)。"""
        kind, args, cwd, clear, requires = TASKS[label]
        if kind == "chain":
            sub_labels: list[str] = args
            for sub in sub_labels:
                if sub not in TASKS:
                    raise ValueError(f"chain '{label}' 引用未知任务：{sub!r}")
            cmd_args = [(sub, *TASKS[sub]) for sub in sub_labels]
        else:
            cmd_args = args
        return kind, cmd_args, cwd, clear, requires

    attach_button(clear_btn, "清屏", *resolve_args("清屏"))

    # 给 tab 配 emoji 图标（key 与 TASK_TABS 一致）
    TAB_ICONS = {
        "下载 (Download)": "📥",
        "诊断 (Diag)": "🔍",
        "检查 (Check)": "✅",
        "编译 (Build)": "🔨",
        "打包 (Package)": "📦",
        "运行 (Run)": "▶️",
        "工具链 (Toolchain)": "🛠",
    }
    # chain 任务列表：渲蓝色 primary 按钮
    CHAIN_LABELS = {label for label, t in TASKS.items() if t[0] == "chain"}

    for tab_name, labels in TASK_TABS.items():
        # tab 内容：QScrollArea 包 grid，让按钮多时滚动而不是被压缩
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        # 滚动条样式
        scroll.setStyleSheet("QScrollBar:vertical { width: 8px; background: #f6f8fa; }"
                             "QScrollBar::handle:vertical { background: #d0d7de; border-radius: 4px; min-height: 20px; }"
                             "QScrollBar::handle:vertical:hover { background: #afb8c1; }"
                             "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }")

        tab_widget = QWidget()
        grid = QGridLayout(tab_widget)
        grid.setContentsMargins(10, 10, 10, 10)
        grid.setHorizontalSpacing(6)
        grid.setVerticalSpacing(4)
        for i, label in enumerate(labels):
            b = QPushButton(label)
            b.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
            b.setMinimumHeight(30)  # 单行按钮最小 30px
            b.setMaximumHeight(36)  # 限定最大避免被撑大
            b.setToolTip(label)  # hover 显示完整名字
            if label in CHAIN_LABELS:
                b.setObjectName("primary")
                # chain 按钮：去掉 "(chain: ...)" 副标题（过长），保留主标题
                short = label.split(" (")[0]
                b.setText("▶ " + short)
                b.setToolTip(label + "\n（chain 任务：自动串行跑多个子任务）")
            attach_button(b, label, *resolve_args(label))
            grid.addWidget(b, i // COLS, i % COLS)
        for col in range(COLS):
            grid.setColumnStretch(col, 1)

        scroll.setWidget(tab_widget)
        icon = TAB_ICONS.get(tab_name, "")
        notebook.addTab(scroll, f"{icon}  {tab_name}" if icon else tab_name)
    # 第一个 tab：环境设置（直接用 env_tab widget）
    notebook.insertTab(0, env_tab, "🔧  环境设置")
    # 默认选中「环境设置」tab，启动就能看到代理/镜像
    notebook.setCurrentIndex(0)
    panel_layout.addWidget(notebook)
    # 控制面板占满左栏高度；minHeight 保底；内容用 AlignTop 顶住
    panel_group.setMinimumHeight(420)
    panel_group.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Expanding)
    left_layout.addWidget(panel_group, stretch=1)

    # ── 右侧：暗色输出区 + 顶部工具栏 ──
    right_top = QHBoxLayout()
    right_top.setSpacing(4)
    right_top.addWidget(QLabel("📋  日志输出"))
    right_top.addStretch(1)
    # 复制全部
    def copy_all():
        QApplication.clipboard().setText(output.toPlainText())
    copy_btn = QPushButton("📋  复制")
    copy_btn.setMaximumWidth(80)
    copy_btn.clicked.connect(copy_all)
    right_top.addWidget(copy_btn)
    # 滚到底
    def scroll_to_end():
        sb = output.verticalScrollBar()
        sb.setValue(sb.maximum())
    bottom_btn = QPushButton("⤵  滚到底")
    bottom_btn.setMaximumWidth(90)
    bottom_btn.clicked.connect(scroll_to_end)
    right_top.addWidget(bottom_btn)
    right_layout.addLayout(right_top)

    # ── 输出区（暗色等宽字体）──
    output = QTextEdit()
    output.setReadOnly(True)
    output.setLineWrapMode(QTextEdit.NoWrap)
    # QSS 已经设了等宽字体 + 暗色背景，这里只 set 一个保底
    output.setFont(QFont("JetBrains Mono", 10))
    right_layout.addWidget(output, stretch=1)

    # ── Runner + QTimer ──
    runner = Runner(
        output=output,
        status_bar=status_bar,
        status_left=status_left,
        status_center=status_center,
        status_right=status_right,
        buttons_provider=lambda: list(btns.values()),
        toolchain=toolchain,
        proxy=proxy,
        pub_mirror=pub_mirror,
        device_getter=lambda: device_edit.text().strip() or "linux",
    )

    poll_timer = QTimer()
    poll_timer.setInterval(50)
    poll_timer.timeout.connect(runner.drain)
    poll_timer.start()

    spinner_timer = QTimer()
    spinner_timer.setInterval(200)
    spinner_timer.timeout.connect(runner.tick_spinner)
    spinner_timer.start()

    # 欢迎文字 —— 加分隔线让启动信息更醒目
    # 合并成一次 _log 调用，避免多次滚到底导致前几行被 viewport 裁掉
    # banner 控制在 5 行以内，确保小窗口也能完整显示
    sep = "─" * 64
    if mode == "missing":
        welcome = (
            f"[提示] {mode_text}\n"
            "请安装 fvm（https://fvm.app）或确保系统 flutter/dart 在 PATH 上。\n"
        )
    else:
        git_part = f"git: {branch} @ {sha}  ·  " if branch != "?" else ""
        total_tabs = len(TASK_TABS) + 1  # +1 = 环境设置 tab
        tab_label = f"共 {tasks_count} 个任务（{total_tabs} 个 tab）"
        welcome = (
            f"┌{sep}┐\n"
            f"│  LocalSend 工具箱  v{version:<14} {git_part:<24}│\n"
            f"│  {mode_text:<60}│\n"
            f"│  {tab_label:<60}│\n"
            f"└{sep}┘\n"
            "点上面 tab 按钮跑任务。chain 任务自动串行；长任务转圈说明在跑。\n"
        )
    runner._log(welcome)
    # 状态栏初始文本（proxy 概要由 refresh_proxy_summary 设置过；这里再确保一次）
    status_left.setText("就绪")
    if not status_right.text():
        status_right.setText(proxy.describe() if proxy.enabled else "代理: 关")

    win.show()

    # --auto <task_name>: 启动后自动跑指定任务，跑完自动关窗。
    # auto_task 在调用方已校验存在于 TASKS。
    if auto_task is not None:
        def _auto_submit():
            kind, args, cwd, clear, requires = TASKS[auto_task]
            runner.submit(auto_task, kind, args, cwd, clear, requires)

        def _auto_quit():
            # runner.busy 由 Runner 在 done 事件里清掉；轮询到 False 就退出
            if not runner.busy:
                QTimer.singleShot(300, app.quit)
            else:
                QTimer.singleShot(1000, _auto_quit)

        def _start_quit_check():
            # 等任务真正被 submit 之后再开始轮询退出（避免误判「启动即空载」）
            if runner.current:
                QTimer.singleShot(2000, _auto_quit)
            else:
                QTimer.singleShot(500, _start_quit_check)

        QTimer.singleShot(500, _auto_submit)
        QTimer.singleShot(1500, _start_quit_check)

    sys.exit(app.exec())


def dry_run() -> int:
    """Sanity check without opening a window.

    Verifies:
      * `TASKS` labels are unique.
      * Every label in `TASK_TABS` exists in `TASKS`.
      * `build_cmd` resolves the "清屏" task correctly (uses kind=None, no
        shell, no cwd, no deps — the simplest non-trivial path).
      * `detect_toolchain` does not error out (it just runs `which`).
      * Every shell task's `fvm` prefix is paired with a real dependency, so
        `build_cmd` can strip it under "system" mode.
    """
    issues: list[str] = []

    # 1. Unique labels.
    if len(set(TASKS)) != len(TASKS):
        dupes = sorted({l for l in TASKS if list(TASKS).count(l) > 1})
        issues.append(f"TASKS has duplicate labels: {dupes}")

    # 2. Every tab label exists.
    for tab, labels in TASK_TABS.items():
        for l in labels:
            if l not in TASKS:
                issues.append(f"tab '{tab}' references missing task: {l!r}")

    # 3. The 清屏 task resolves to no command at all.
    clear = TASKS["清屏"]
    if clear != (None, None, None, True, []):
        issues.append(f"清屏 task definition drifted: {clear}")
    cmd = build_cmd(detect_toolchain(), *clear[:4])
    if cmd != []:
        issues.append(f"清屏 should build to [], got {cmd!r}")

    # 4. Toolchain detection does not throw.
    tc = detect_toolchain()
    print(f"[toolchain] {tc}")

    # 4b. Every task type must resolve through build_cmd without raising
    # ValueError. Catches missing branches when a new kind is introduced.
    for label, t in TASKS.items():
        kind, args, cwd, _clear, _deps = t
        if kind is None and args is None:
            continue
        try:
            cmd = build_cmd(tc, kind, args, cwd)
        except (ValueError, FileNotFoundError) as e:
            # FileNotFoundError is fine — it means a dep is missing on this
            # machine, not that the dispatcher is wrong.
            if isinstance(e, ValueError):
                issues.append(f"build_cmd 不知道类型 {kind!r} (task: {label!r}): {e}")

    # 5. Every shell task uses `fvm` only when the dependency includes fvm.
    for label, t in TASKS.items():
        if t[0] != "shell":
            continue
        shell = t[1]
        deps = t[4]
        if "fvm " in shell and "fvm" not in deps and "flutter" not in deps and "dart" not in deps:
            issues.append(f"shell task {label!r} uses fvm but deps={deps}")

    # 6. If --auto <task> is in argv, the task name must exist.
    if "--auto" in sys.argv:
        idx = sys.argv.index("--auto")
        if idx + 1 >= len(sys.argv):
            issues.append("--auto needs a task name after it")
        elif sys.argv[idx + 1] not in TASKS:
            issues.append(f"--auto task {sys.argv[idx + 1]!r} not in TASKS")

    if issues:
        print("[FAIL] ui.py dry-run found issues:")
        for i in issues:
            print(f"  - {i}")
        return 1
    print(f"[OK] ui.py dry-run: {len(TASKS)} tasks across {len(TASK_TABS) + 1} tabs (含环境设置), no issues")
    return 0


if __name__ == "__main__":
    import sys
    if "--dry-run" in sys.argv:
        sys.exit(dry_run())

    # --auto <task_name>: 启动后自动跑指定任务，跑完自动关窗。
    # 先校验任务名（拼写错就早死，不弹空窗），再交给 main()。
    auto_task = None
    if "--auto" in sys.argv:
        idx = sys.argv.index("--auto")
        if idx + 1 >= len(sys.argv):
            print("[ui.py] 错误：--auto 需要 task 名作为下一个参数", file=sys.stderr)
            sys.exit(2)
        auto_task = sys.argv[idx + 1]
        if auto_task not in TASKS:
            print(f"[ui.py] 错误：--auto 任务 '{auto_task}' 不在 TASKS 里", file=sys.stderr)
            print(f"  示例可用任务: flutter test / flutter analyze / PR5 flutter analyze (...)", file=sys.stderr)
            sys.exit(2)

    main(auto_task=auto_task)
