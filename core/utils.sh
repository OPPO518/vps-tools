#!/bin/bash

# =========================================================
#  模块: core/utils.sh
#  功能: 全局变量、颜色、通用辅助函数 (修复强化版)
# =========================================================

# ===== 全局颜色变量 =====
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'
gl_hui='\033[37m'

# ===== 辅助函数: 获取国旗 Emoji =====
get_flag_local() {
    case "$1" in
        CN) echo "🇨🇳" ;; HK) echo "🇭🇰" ;; MO) echo "🇲🇴" ;; TW) echo "🇹🇼" ;;
        US) echo "🇺🇸" ;; JP) echo "🇯🇵" ;; KR) echo "🇰🇷" ;; SG) echo "🇸🇬" ;;
        RU) echo "🇷🇺" ;; DE) echo "🇩🇪" ;; GB) echo "🇬🇧" ;; FR) echo "🇫🇷" ;;
        NL) echo "🇳🇱" ;; CA) echo "🇨🇦" ;; AU) echo "🇦🇺" ;; IN) echo "🇮🇳" ;;
        TH) echo "🇹🇭" ;; VN) echo "🇻🇳" ;; MY) echo "🇲🇾" ;; ID) echo "🇮🇩" ;;
        BR) echo "🇧🇷" ;; ZA) echo "🇿🇦" ;; IT) echo "🇮🇹" ;; ES) echo "🇪🇸" ;;
        *) echo "🌐" ;; 
    esac
}

# ===== 辅助函数: IP信息获取 (高可用防限流版) =====
ip_address() {
    # 增加多节点回源，防止单一 API 挂掉或触发限流导致菜单加载卡死
    get_public_ip() {
        local ip
        ip=$(curl -s -4 --max-time 2 https://api.ipify.org 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s -4 --max-time 2 https://ipv4.icanhazip.com 2>/dev/null)
        [ -z "$ip" ] && ip=$(curl -s -4 --max-time 2 https://ipinfo.io/ip 2>/dev/null)
        echo "$ip"
    }
    
    get_local_ip() { 
        ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || hostname -I 2>/dev/null | awk '{print $1}'
    }
    
    public_ip=$(get_public_ip)
    isp_info=$(curl -s --max-time 2 http://ipinfo.io/org 2>/dev/null)
    
    if echo "$isp_info" | grep -Eiq 'mobile|unicom|telecom'; then 
        ipv4_address=$(get_local_ip)
    else 
        ipv4_address="$public_ip"
    fi
    
    # 缩短 IPv6 探测超时，无 IPv6 机器快速跳过
    ipv6_address=$(curl -s -6 --max-time 1 https://api64.ipify.org 2>/dev/null || curl -s -6 --max-time 1 https://ipv6.icanhazip.com 2>/dev/null)
    country_code=$(curl -s --max-time 2 https://ipinfo.io/country 2>/dev/null | tr -d '\n')
    flag=$(get_flag_local "$country_code")
}

# ===== 辅助函数: 网络流量统计 (增加 OpenVZ 网卡兼容) =====
output_status() {
    output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        # 新增 venet 网卡匹配，兼容 OpenVZ 等特殊虚拟化环境
        $1 ~ /^(eth|ens|enp|eno|venet)[0-9]+/ { rx_total += $2; tx_total += $10 }
        END {
            rx_units = "B"; tx_units = "B";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "K"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "M"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "G"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "K"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "M"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "G"; }
            printf("%.2f%s %.2f%s\n", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)
    rx=$(echo "$output" | awk '{print $1}')
    tx=$(echo "$output" | awk '{print $2}')
}

# ===== 辅助函数: 时区检测 =====
current_timezone() {
    if grep -q 'Alpine' /etc/issue 2>/dev/null; then 
        date +"%Z %z"
    else 
        timedatectl | grep "Time zone" | awk '{print $3}'
    fi
}

# ===== 辅助函数: 提取真实 SSH 端口 (防自锁增强版) =====
detect_ssh_port() {
    local ports=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | paste -sd "," -)
    echo "${ports:-22}"
}

# ===== 辅助函数: 自动放行端口 (UFW 适配版) =====
ensure_port_open() {
    local port="$1"
    
    # 检查是否安装了 ufw 并且处于 active 状态
    if command -v ufw &>/dev/null; then
        if ufw status | grep -qw "active"; then
            # [修复] grep -qW 是无效参数，改为合法的 -qw (全词匹配)
            if ! ufw status | grep -qw "$port"; then
                echo -e "${gl_huang}检测到 UFW 防火墙运行中，正在自动放行端口 $port...${gl_bai}"
                # 静默放行 tcp 和 udp
                ufw allow "$port"/tcp >/dev/null 2>&1
                ufw allow "$port"/udp >/dev/null 2>&1
            fi
        fi
    fi
}

# =========================================================
#  幂等辅助（通用版）：各模块独立的 状态 / 清单 / 备份
#  目录 /etc/vps-tools 在 git 仓库之外，不会被 reset --hard 抹掉
#  每个模块一个 <module>.state 和 <module>.manifest，备份在 backup/<module>/
# =========================================================
VPS_TOOLS_STATE_DIR="/etc/vps-tools"

state_file_for()    { echo "${VPS_TOOLS_STATE_DIR}/$1.state"; }
manifest_file_for() { echo "${VPS_TOOLS_STATE_DIR}/$1.manifest"; }
backup_dir_for()    { echo "${VPS_TOOLS_STATE_DIR}/backup/$1"; }

# 把绝对路径转成安全的备份文件名（同时处理 / 与 Windows 的 \ 和盘符冒号）
config_backup_key() {
    local key="$1"
    key="${key//\//_}"
    key="${key//\\/_}"
    key="${key//:/_}"
    echo "$key"
}

# 某模块是否已经执行过
module_state_is_done() {
    local f=$(state_file_for "$1")
    [ -f "$f" ] && grep -q '^DONE=1$' "$f"
}

# 读取某模块上次执行时间（供主菜单显示）
module_state_last_run() {
    local f=$(state_file_for "$1")
    [ -f "$f" ] && grep '^LAST_RUN=' "$f" | cut -d= -f2-
}

# 标记某模块执行完成
module_state_mark_done() {
    local module="$1"
    mkdir -p "$VPS_TOOLS_STATE_DIR"
    {
        echo "DONE=1"
        echo "LAST_RUN=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$(state_file_for "$module")"
}

# 清除某模块的完成标记（还原后调用）
module_state_clear() {
    rm -f "$(state_file_for "$1")"
}

# 注册"会被某模块改写"的配置文件（可一次传多个）：
# 首次注册时备份原始版本，后续重复注册不覆盖备份；清单去重。
# 即使文件当前不存在也登记，便于重跑时删除脚本生成的文件。
track_config() {
    local module="$1"; shift
    [ -z "$module" ] && return 1
    local manifest=$(manifest_file_for "$module")
    local bdir=$(backup_dir_for "$module")
    mkdir -p "$bdir"
    local target key backup
    for target in "$@"; do
        [ -z "$target" ] && continue
        key=$(config_backup_key "$target")
        backup="${bdir}/${key}"
        if [ -f "$target" ] && [ ! -f "$backup" ]; then
            cp -a "$target" "$backup"
        fi
        grep -qxF "$target" "$manifest" 2>/dev/null || echo "$target" >> "$manifest"
    done
}

# 还原某模块所有改写过的配置文件：
# 有备份的还原成执行前的版本；原本不存在、由脚本生成的文件直接删除。
restore_tracked_configs() {
    local module="$1"
    local manifest=$(manifest_file_for "$module")
    [ -f "$manifest" ] || return 0
    local bdir=$(backup_dir_for "$module")
    local target key backup
    while IFS= read -r target; do
        [ -z "$target" ] && continue
        key=$(config_backup_key "$target")
        backup="${bdir}/${key}"
        if [ -f "$backup" ]; then
            cp -a "$backup" "$target"
        elif [ -e "$target" ]; then
            rm -f "$target"
        fi
    done < "$manifest"
}

# ---- 兼容第一项旧函数名的包装（system.sh 已改用通用版，此处保留以防外部引用）----
init_state_is_done()   { module_state_is_done init; }
init_state_last_run()  { module_state_last_run init; }
init_state_mark_done() { module_state_mark_done init; }
init_state_clear()     { module_state_clear init; }

# 通用"执行前确认"交互：已执行过则询问是否重跑，选 y 则还原并清标记；选 n 返回 1。
# 用法：confirm_rerun <module> <显示名称>  返回 0=继续执行  1=取消
confirm_rerun() {
    local module="$1" label="$2"
    if module_state_is_done "$module"; then
        echo -e "${gl_huang}检测到本机已完成过${label}：${gl_bai}$(module_state_last_run "$module")"
        echo -e "${gl_hui}重复执行会先还原上次写入的配置，再重新生成，避免参数叠加。${gl_bai}"
        read -p "是否仍要重新执行? (y/n): " redo
        if [[ ! "$redo" =~ ^[yY]$ ]]; then
            echo -e "${gl_lv}已取消，未改动任何配置。${gl_bai}"
            sleep 1
            return 1
        fi
        echo -e "${gl_kjlan}>>> 正在还原上次写入的配置文件...${gl_bai}"
        restore_tracked_configs "$module"
        module_state_clear "$module"
    fi
    return 0
}
