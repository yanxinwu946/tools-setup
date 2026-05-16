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
        f) 
            OVERWRITE=true 
            ;;
        *) 
            echo "用法: $0 [-f (覆盖安装)]"
            exit 1 
            ;;
    esac
done

# 检查权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

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
    "projectdiscovery/mapcidr"
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
    local repo="$1"
    local bin_name="${repo##*/}"
    local target_path="/usr/local/bin/$bin_name"

    # 判断是否跳过安装
    if [[ -f "$target_path" && "$OVERWRITE" == false ]]; then
        echo -e "${BLUE}[跳过]${NC} $bin_name 已存在"
        return
    fi

    echo -e "\n${BLUE}[正在部署]${NC} $bin_name 来自 $repo"

    local assets_json
    assets_json=$(curl -s -H "User-Agent: Mozilla/5.0" "https://api.github.com/repos/$repo/releases/latest")

    local url
    url=$(echo "$assets_json" | jq -r '
        [ .assets[] | .browser_download_url | select(test("linux"; "i")) ] | 
        ( map(select(test("amd64|x86_64|x64"; "i")))[0] // 
          map(select(test("i386|arm|mips|win|osx|mac|apple|freebsd"; "i") | not))[0] )
    ')

    if [[ -z "$url" || "$url" == "null" ]]; then
        echo -e "${RED}[错误]${NC} 无法在 $repo 中找到合适的二进制包"
        return
    fi

    local tmp_dir="/tmp/setup_$bin_name"
    local tmp_file="$tmp_dir/package"
    mkdir -p "$tmp_dir"
    
    echo -e "${BLUE}[下载]${NC} $url"
    wget -qO "$tmp_file" "$url"

    case "$url" in
        *.zip)
            unzip -o "$tmp_file" -d "$tmp_dir" > /dev/null
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$tmp_file" -C "$tmp_dir"
            ;;
        *.gz)
            gunzip -c "$tmp_file" > "$tmp_dir/$bin_name"
            ;;
        *)
            # 针对直接发布的单文件二进制
            mv "$tmp_file" "$target_path"
            chmod +x "$target_path"
            rm -rf "$tmp_dir"
            return
            ;;
    esac

    # 智能定位二进制文件：提取出第一个符合条件的路径，避免 find 多次移动覆盖
    local found_bin
    found_bin=$(find "$tmp_dir" -type f -executable \( -name "$bin_name" -o -name "$bin_name*" \) -print -quit)
    
    if [[ -z "$found_bin" ]]; then
        found_bin=$(find "$tmp_dir" -type f -executable -print -quit)
    fi

    # 最终安装与权限赋予
    if [[ -n "$found_bin" ]]; then
        mv "$found_bin" "$target_path"
        chmod +x "$target_path"
    else
        echo -e "${RED}[错误]${NC} 未能在解压目录中找到可执行的二进制文件"
    fi

    rm -rf "$tmp_dir"
}

# -------------------------------------------------------------------
# 主逻辑
# -------------------------------------------------------------------
for repo in "${TOOLS[@]}"; do
    download_tool "$repo"
done

# GF 规则库特殊处理预留
# if [[ ! -d "$HOME/.gf" || "$OVERWRITE" == true ]]; then
#     echo -e "\n${BLUE}[配置]${NC} 下载/更新 GF Patterns..."
#     rm -rf "$HOME/.gf" && mkdir -p "$HOME/.gf"
#     git clone --depth 1 https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns > /dev/null 2>&1
#     cp /tmp/Gf-Patterns/*.json "$HOME/.gf/"
#     rm -rf /tmp/Gf-Patterns
# fi

# 验证安装结果
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}            所有工具部署完成！          ${NC}"
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
