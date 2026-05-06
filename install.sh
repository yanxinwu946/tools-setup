#!/bin/bash
# -------------------------------------------------------------------
# Ubuntu/Debian 安全工具一键部署脚本
# 特点：支持 -f 覆盖更新、自动适配 x64 架构
# -------------------------------------------------------------------

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 参数解析
OVERWRITE=false
while getopts "f" opt; do
  case $opt in
    f) OVERWRITE=true ;;
    *) echo "用法: $0 [-f (覆盖安装)]"; exit 1 ;;
  esac
done

# 检查权限
[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 sudo 运行此脚本${NC}" && exit 1

echo -e "${BLUE}开始初始化基础环境...${NC}"
apt-get update && apt-get install -y curl wget unzip jq tar git

# -------------------------------------------------------------------
# 工具定义列表 (仓库路径)
# -------------------------------------------------------------------
TOOLS=(
    "projectdiscovery/subfinder"
    "projectdiscovery/httpx"
    "projectdiscovery/nuclei"
    "projectdiscovery/katana"
    "projectdiscovery/naabu"
    "projectdiscovery/dnsx"
    "projectdiscovery/asnmap"
    "ffuf/ffuf"
    "lc/gau"
    "tomnomnom/anew"
    "hahwul/dalfox"
    "findomain/findomain"
    "Sh1Yo/x8"
    "tomnomnom/waybackurls"
    "incogbyte/shosubgo"
    "tomnomnom/gf"
)

# 核心下载函数
download_tool() {
    local repo=$1
    local bin_name="${repo##*/}"
    local target_path="/usr/local/bin/$bin_name"

    # 判断是否跳过安装
    if [[ -f "$target_path" && "$OVERWRITE" == false ]]; then
        echo -e "${BLUE}[跳过]${NC} $bin_name 已存在"
        return
    fi

    echo -e "\n${BLUE}[正在部署]${NC} $bin_name 来自 $repo"

    local assets_json=$(curl -s -H "User-Agent: Mozilla/5.0" "https://api.github.com/repos/$repo/releases/latest")

    # 策略 1：白名单模式
    local url=$(echo "$assets_json" | jq -r ".assets[] | select(.name | test(\"linux\"; \"i\")) | select(.name | test(\"amd64|x86_64|x64\"; \"i\")) | .browser_download_url" | head -n 1)

    # 策略 2：黑名单模式
    if [ -z "$url" ] || [ "$url" == "null" ]; then
        url=$(echo "$assets_json" | jq -r ".assets[] | select(.name | test(\"linux\"; \"i\")) | select(.name | test(\"i386|arm|mips|win|osx|mac|apple|freebsd\"; \"i\") | not) | .browser_download_url" | head -n 1)
    fi

    if [ -z "$url" ] || [ "$url" == "null" ]; then
        echo -e "${RED}[错误]${NC} 无法在 $repo 中找到合适的二进制包"
        return
    fi

    local tmp_dir="/tmp/setup_$bin_name"
    mkdir -p "$tmp_dir"
    local tmp_file="$tmp_dir/package"
    
    echo -e "${BLUE}[下载]${NC} $url"
    wget -qO "$tmp_file" "$url"

    # 解压逻辑
    if [[ "$url" == *.zip ]]; then
        unzip -o "$tmp_file" -d "$tmp_dir" > /dev/null
    elif [[ "$url" == *.tar.gz || "$url" == *.tgz ]]; then
        tar -xzf "$tmp_file" -C "$tmp_dir"
    elif [[ "$url" == *.gz ]]; then
        cp "$tmp_file" "$tmp_dir/$bin_name.gz"
        gunzip -f "$tmp_dir/$bin_name.gz"
    else
        # 针对直接发布的单文件二进制
        mv "$tmp_file" "$target_path"
        chmod +x "$target_path"
        rm -rf "$tmp_dir"
        return
    fi

    # 智能定位二进制文件并安装
    find "$tmp_dir" -type f -executable \( -name "$bin_name" -o -name "$bin_name*" \) -exec mv {} "$target_path" \; 2>/dev/null
    if [ ! -f "$target_path" ]; then
        find "$tmp_dir" -type f -executable -exec mv {} "$target_path" \; 2>/dev/null | head -n 1
    fi

    chmod +x "$target_path"
    rm -rf "$tmp_dir"
}

# -------------------------------------------------------------------
# 主逻辑
# -------------------------------------------------------------------
for repo in "${TOOLS[@]}"; do
    download_tool "$repo"
done

# GF 规则库特殊处理
# if [[ ! -d "$HOME/.gf" || "$OVERWRITE" == true ]]; then
#     echo -e "\n${BLUE}[配置]${NC} 下载/更新 GF Patterns..."
#     rm -rf "$HOME/.gf" && mkdir -p "$HOME/.gf"
#     git clone --depth 1 https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns > /dev/null 2>&1
#     cp /tmp/Gf-Patterns/*.json "$HOME/.gf/"
#     rm -rf /tmp/Gf-Patterns
# fi

# 验证安装结果
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}            所有工具部署完成！      ${NC}"
echo -e "${GREEN}========================================${NC}"

for repo in "${TOOLS[@]}"; do
    bin="${repo##*/}"
    if command -v "$bin" &> /dev/null; then
        echo -e "✅ $bin : $(which $bin)"
    else
        echo -e "❌ $bin : 未找到"
    fi
done

echo -e "\n${BLUE}提示：${NC}使用 ${GREEN}-f${NC} 参数可强制更新所有工具至最新版本。"
