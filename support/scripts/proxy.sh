#!/usr/bin/env bash
# Source this script to set HTTP/HTTPS proxy for the current shell.
# 跟 ui.py 的 ProxyConfig 默认值保持一致。
#
# 用法:
#   source support/scripts/proxy.sh         # 临时开启
#   source support/scripts/proxy.sh off     # 临时关闭
#   echo $http_proxy                        # 验证
#
# 想每次新终端自动开：加到 ~/.bashrc 末尾:
#   [ -f /home/bv/code/localsend/support/scripts/proxy.sh ] && source /home/bv/code/localsend/support/scripts/proxy.sh

PROXY_URL="${PROXY_URL:-http://127.0.0.1:7890}"
NO_PROXY_LIST="${NO_PROXY_LIST:-localhost,127.0.0.1,::1,.local,.internal}"

if [ "$1" = "off" ]; then
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    echo "[proxy] 关"
    return 0 2>/dev/null || exit 0
fi

# 同时设大小写：cargo 认小写，git/curl 认大写，少数工具只认一种。
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
# SOCKS 代理给 git over ssh 用
export all_proxy="socks5://127.0.0.1:7890"
export ALL_PROXY="socks5://127.0.0.1:7890"
export no_proxy="$NO_PROXY_LIST"
export NO_PROXY="$NO_PROXY_LIST"

# apt 走代理（不常用，留作参考）
# sudo http_proxy=$PROXY_URL apt update

# cargo: ~/.cargo/config.toml 里 [source] / [net] 才生效，环境变量对 cargo 不全
# 已有 ui.py「cargo 镜像源 (写到 ~/.cargo/config.toml, 清华)」按钮

# git: HTTP 协议走环境变量。SSH 协议要走 ~/.ssh/config 加 ProxyCommand。
git config --global http.proxy "$PROXY_URL" 2>/dev/null || true
git config --global https.proxy "$PROXY_URL" 2>/dev/null || true

echo "[proxy] 开 → $PROXY_URL"
echo "[proxy] NO_PROXY → $NO_PROXY_LIST"
echo "[proxy] 验证: curl -sI https://pub.dev"
