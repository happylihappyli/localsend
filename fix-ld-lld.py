#!/usr/bin/env python3
"""修 ld.lld 死循环软链接。

问题：
  /usr/lib/llvm-18/bin/ld.lld  -> /usr/bin/ld.lld-18
  /usr/bin/ld.lld-18           -> ../lib/llvm-18/bin/ld.lld  (← 指回去了)
  → 死循环 → 报 "符号链接的层数过多" / Flutter 报 "Failed to find ld.lld"

解决：
  /usr/lib/llvm-18/bin/ld.lld  -> /usr/lib/llvm-18/bin/lld  (同目录真二进制)

用法：
  python3 fix-ld-lld.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

LD_LLD = Path("/usr/lib/llvm-18/bin/ld.lld")
LDD_LLD_18 = Path("/usr/bin/ld.lld-18")
REAL_LLD = Path("/usr/lib/llvm-18/bin/lld")


def is_broken_link(p: Path) -> bool:
    """软链接存在但 target 解析失败（含循环）。"""
    if not p.is_symlink():
        return False
    try:
        p.resolve(strict=True)
        return False
    except (OSError, RuntimeError):
        return True


def main() -> int:
    # 1. 探测状态
    print("== 探测当前状态 ==")
    print(f"  {LD_LLD}: exists={LD_LLD.exists()}  is_link={LD_LLD.is_symlink()}")
    if LD_LLD.is_symlink():
        print(f"    target: {os.readlink(LD_LLD)}")
    print(f"  {LDD_LLD_18}: exists={LDD_LLD_18.exists()}  is_link={LDD_LLD_18.is_symlink()}")
    if LDD_LLD_18.is_symlink():
        print(f"    target: {os.readlink(LDD_LLD_18)}")
    print(f"  {REAL_LLD}: exists={REAL_LLD.exists()}  is_link={REAL_LLD.is_symlink()}")

    # 2. 判断是否需要修
    need_fix = is_broken_link(LD_LLD) or (not REAL_LLD.exists())
    if not need_fix and LD_LLD.is_symlink():
        target = os.readlink(LD_LLD)
        if Path(target).is_absolute() and not Path(target).exists():
            need_fix = True
    if not need_fix:
        # 再做一次实调用测试
        try:
            r = subprocess.run([str(LD_LLD), "--version"], capture_output=True, timeout=5)
            if r.returncode != 0 or b"ld.lld" not in r.stdout and b"LLD" not in r.stdout:
                need_fix = True
        except (OSError, subprocess.TimeoutExpired):
            need_fix = True

    if not need_fix:
        print("\n[OK] ld.lld 已经是好的，无需修复")
        print(f"     {LD_LLD} → {os.readlink(LD_LLD)}")
        return 0

    print("\n== 需要修复 ==")
    print(f"  删 {LD_LLD} (旧的循环链接)")
    print(f"  建 {LD_LLD} → {REAL_LLD} (同目录真二进制)")

    # 3. 找 root 工具（pkexec 优先，弹 GUI 认证框；fallback 到 sudo + 终端）
    if shutil.which("pkexec"):
        cmd = ["pkexec", sys.executable, "-c",
               f"import os; os.unlink({str(LD_LLD)!r}); os.symlink({str(REAL_LLD)!r}, {str(LD_LLD)!r})"]
        print("  用 pkexec（弹 GUI 认证框）")
    else:
        cmd = ["sudo", "bash", "-c",
               f"rm -f {LD_LLD} && ln -s {REAL_LLD} {LD_LLD}"]
        print("  用 sudo（终端输入密码）")

    rc = subprocess.call(cmd)
    if rc != 0:
        print(f"\n[FAIL] 修复失败 rc={rc}")
        return rc

    # 4. 验证
    print("\n== 验证 ==")
    print(f"  {LD_LLD}: exists={LD_LLD.exists()}  is_link={LD_LLD.is_symlink()}")
    if LD_LLD.is_symlink():
        print(f"    target: {os.readlink(LD_LLD)}")
    try:
        r = subprocess.run([str(LD_LLD), "--version"], capture_output=True, timeout=5)
        first_line = r.stdout.decode(errors="replace").splitlines()[0] if r.stdout else "(无输出)"
        print(f"  ld.lld --version: rc={r.returncode}  first line: {first_line}")
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"  [FAIL] ld.lld 仍无法调用: {e}")
        return 1
    print("\n[OK] 修复完成。现在 flutter build linux 应该能找到 ld.lld 了。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
