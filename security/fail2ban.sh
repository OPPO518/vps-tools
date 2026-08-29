#!/bin/bash

# =================================================================
#  企业级 UFW + Fail2ban 核心网关引擎 (极简重构版)
#  依赖: 必须由主框架 (x.sh) source 调用，并由其提供颜色变量
# =================================================================

# [输入校验] 端口与 IP 校验直接复用你写的高质量正则
validate_port() {
    local raw_input="$1"
    local cleaned=$(echo "$raw_input" | tr -d ' ' | sed 's/，/,/g' | tr ':' '-')
    [ -z "$cleaned" ] && return 1
    IFS=',' read -r -a port_array <<< "$cleaned"
    for p in "${port_array[@]}"; do
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then return 1; fi
        elif [[ "$p" =~ ^[0-9]+-[0-9]+$ ]]; then
            local p1=$(echo "$p" | cut -d'-' -f1)
            local p2=$(echo "$p" | cut -d'-' -f2)
            if [ "$p1" -lt 1 ] || [ "$p1" -gt 65535 ] || [ "$p2" -lt 1 ] || [ "$p2" -gt 65535 ] || [ "$p1" -ge "$p2" ]; then return 1; fi
        else
            return 1
        fi
    done
    VALIDATED_PORT="$cleaned"
    return 0
}

validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then return 0; fi
    return 1
}

detect_ssh_port() {
    local ports=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | paste -sd "," -)
    echo "${ports:-22}"
}

# =================================================================
# 初始化 UFW & Fail2ban (接管系统防御)
# =================================================================
init_ufw_fail2ban() {
    echo -e "${gl_huang}>>> 正在初始化 UFW & Fail2ban 安全矩阵...${gl_bai}"
    apt update -y >/dev/null 2>&1 && apt install -y ufw fail2ban >/dev/null 2>&1

    local ssh_p=$(detect_ssh_port)
    
    echo "y" | ufw reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    
    IFS=',' read -r -a ssh_array <<< "$ssh_p"
    for p in "${ssh_array[@]}"; do
        ufw allow "$p"/tcp comment 'SSH_Lifeline' >/dev/null 2>&1
    done
    
    echo "y" | ufw enable >/dev/null 2>&1

    # 配置 Fail2ban 使用 systemd 和 UFW
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
bantime  = 86400
findtime = 600
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port    = $ssh_p
backend = systemd
EOF

    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    echo -e "${gl_lv}✔ 初始化完成！UFW & Fail2ban 已成功接管。${gl_bai}"
    sleep 2
}

# =================================================================
# UI 交互模块 (取代原 nftables_management)
# =================================================================
ufw_management() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${gl_huang}>>> 尚未安装 UFW，准备静默安装...${gl_bai}"
        apt update -y >/dev/null 2>&1 && apt install -y ufw >/dev/null 2>&1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#         高阶防火墙与流量调度中心 (UFW版)       #"
        echo -e "################################################${gl_bai}"
        
        local ufw_status=$(ufw status | grep -w "Status: active")
        
        if [ -n "$ufw_status" ]; then
            echo -e "底层引擎: ${gl_lv}UFW Active [✔ 已接管]${gl_bai}"
            echo -e "防爆破层: ${gl_lv}Fail2ban [✔ 已联动]${gl_bai}"
            echo -e "防自锁层: ${gl_lv}SSH Port(s) $(detect_ssh_port) [✔ 已保护]${gl_bai}"
            echo "------------------------------------------------"
            echo -e "${gl_kjlan}当前活动规则 (输入 3 可按序号删除):${gl_bai}"
            ufw status numbered | grep -v "Status: active"
            echo "------------------------------------------------"
            
            echo -e "${gl_lv} 1.${gl_bai} 添加 [全网放行] 端口"
            echo -e "${gl_lv} 2.${gl_bai} 添加 [定向 IP] 放行端口"
            echo -e "${gl_huang} 3.${gl_bai} 删除规则 (按序号删除，极度舒适)"
            echo -e "------------------------------------------------"
            echo -e "${gl_kjlan} 4.${gl_bai} 查看 Fail2ban 封禁黑名单"
            echo -e "${gl_hong} 8.${gl_bai} 彻底卸载防火墙 (裸奔)"
        else
            echo -e " 当前状态: ${gl_hong}未初始化 (裸奔状态)${gl_bai}"
            echo -e "------------------------------------------------"
            echo -e "${gl_lv} 1.${gl_bai} 一键初始化并开启企业护盾 (UFW + Fail2ban)"
        fi
        
        echo -e "${gl_hui} 0. 返回主菜单${gl_bai}"
        echo -e "------------------------------------------------"
        
        read -p "请输入选项: " choice

        case "$choice" in
            1) 
                if [ -z "$ufw_status" ]; then
                    init_ufw_fail2ban
                else
                    read -p "请输入放行端口 (支持端口段, 例: 80 或 50000:60000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}格式错误！${gl_bai}"; sleep 2; continue
                    fi
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto
                    case "$proto" in
                        1|tcp) ufw allow "$VALIDATED_PORT"/tcp ;;
                        2|udp) ufw allow "$VALIDATED_PORT"/udp ;;
                        *) ufw allow "$VALIDATED_PORT" ;;
                    esac
                    echo -e "${gl_lv}规则已添加！${gl_bai}"; ufw reload >/dev/null; sleep 1
                fi
                ;;
            2)
                if [ -n "$ufw_status" ]; then
                    read -p "请输入白名单 IP: " ip
                    if ! validate_ip "$ip"; then
                        echo -e "${gl_hong}IP格式错误！${gl_bai}"; sleep 2; continue
                    fi
                    read -p "请输入放行端口 (例: 80 或 50000:60000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}端口格式错误！${gl_bai}"; sleep 2; continue
                    fi
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto
                    case "$proto" in
                        1|tcp) ufw allow from "$ip" to any port "$VALIDATED_PORT" proto tcp ;;
                        2|udp) ufw allow from "$ip" to any port "$VALIDATED_PORT" proto udp ;;
                        *) ufw allow from "$ip" to any port "$VALIDATED_PORT" ;;
                    esac
                    echo -e "${gl_lv}定向规则已添加！${gl_bai}"; ufw reload >/dev/null; sleep 1
                fi
                ;;
            3)
                if [ -n "$ufw_status" ]; then
                    echo -e "${gl_huang}请注意看上面列表中的 [序号]${gl_bai}"
                    read -p "请输入要删除的规则序号 (纯数字): " num
                    if [[ "$num" =~ ^[0-9]+$ ]]; then
                        ufw --force delete "$num"
                        echo -e "${gl_lv}规则 [$num] 已删除！${gl_bai}"; sleep 1
                    else
                        echo -e "${gl_hong}无效的序号！${gl_bai}"; sleep 1
                    fi
                fi
                ;;
            4)
                if [ -n "$ufw_status" ]; then
                    clear
                    echo -e "${gl_kjlan}=== Fail2ban SSH 封禁黑名单 ===${gl_bai}"
                    fail2ban-client status sshd
                    echo -e "\n按任意键返回..."
                    read -n 1 -s
                fi
                ;;
            8) 
                if [ -n "$ufw_status" ]; then
                    echo -e "${gl_hong}警告: 这将清空所有规则并关闭防火墙！${gl_bai}"
                    read -p "确定卸载吗？(y/n): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        echo "y" | ufw reset >/dev/null 2>&1
                        ufw disable >/dev/null 2>&1
                        systemctl stop fail2ban >/dev/null 2>&1
                        systemctl disable fail2ban >/dev/null 2>&1
                        echo -e "${gl_lv}系统已回归开放状态。${gl_bai}"; sleep 1
                    fi
                fi
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项${gl_bai}"; sleep 1 ;;
        esac
    done
}
