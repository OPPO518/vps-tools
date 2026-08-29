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
