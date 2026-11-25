#!/bin/bash

# =================================================================
#  企业级防火墙与防爆破引擎 (UFW + Fail2ban) [修复强化版]
#  文件路径: security/ufw.sh
#  依赖: 必须由主框架 (x.sh) source 调用，并由其提供颜色变量
# =================================================================

# 注: detect_ssh_port 由 core/utils.sh 提供，此处不再重复定义。

# --- [输入校验] 验证端口合法性 ---
validate_port() {
    local raw_input="$1"
    # [修复] UFW 必须使用冒号 ':' 表示端口段，此处将中文逗号转英文，横杠转冒号
    local cleaned=$(echo "$raw_input" | tr -d ' ' | sed 's/，/,/g' | tr '-' ':')
    [ -z "$cleaned" ] && return 1
    
    IFS=',' read -r -a port_array <<< "$cleaned"
    for p in "${port_array[@]}"; do
        if [[ "$p" =~ ^[0-9]+$ ]]; then
            if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then return 1; fi
        elif [[ "$p" =~ ^[0-9]+:[0-9]+$ ]]; then # [修复] 匹配冒号分隔的端口段
            local p1=$(echo "$p" | cut -d':' -f1)
            local p2=$(echo "$p" | cut -d':' -f2)
            if [ "$p1" -lt 1 ] || [ "$p1" -gt 65535 ] || [ "$p2" -lt 1 ] || [ "$p2" -gt 65535 ] || [ "$p1" -ge "$p2" ]; then 
                return 1
            fi
        else
            return 1
        fi
    done
    VALIDATED_PORT="$cleaned"
    return 0
}

# --- [输入校验] 验证 IP 地址合法性 ---
validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then return 0; fi
    return 1
}

# =================================================================
# [核心引擎] 初始化 UFW & Fail2ban
# =================================================================
init_ufw_fail2ban() {
    # --- 0. 幂等判断：已初始化则询问；选 n 不改动，选 y 先还原 ---
    confirm_rerun "ufw" "防火墙初始化" || return 0

    echo -e "${gl_huang}>>> 正在初始化 UFW & Fail2ban 安全矩阵...${gl_bai}"

    # 0.5 登记将被改写的配置文件
    track_config "ufw" "/etc/default/ufw" "/etc/fail2ban/jail.local"

    # 1. 安装核心组件
    export DEBIAN_FRONTEND=noninteractive
    apt update >/dev/null 2>&1
    apt install -y ufw fail2ban >/dev/null 2>&1

    # [关键修复] 强制开启 UFW 的 IPv6 支持，防止双栈网络单边断流
    sed -i 's/^IPV6=no/IPV6=yes/g' /etc/default/ufw

    # 2. 获取当前 SSH 端口并初始化 UFW
    local ssh_p=$(detect_ssh_port)

    # 备份现有规则：在 reset 之前把当前规则快照存下来，避免误清后无法恢复
    local ufw_backup_dir=$(backup_dir_for "ufw")
    mkdir -p "$ufw_backup_dir"
    ufw status numbered > "${ufw_backup_dir}/rules.before.$(date +%F_%H%M%S).txt" 2>/dev/null
    cp -a /etc/fail2ban/jail.local "${ufw_backup_dir}/jail.local.before.$(date +%F_%H%M%S)" 2>/dev/null
    echo -e "${gl_hui}已备份当前 UFW 规则到 ${ufw_backup_dir}${gl_bai}"

    echo "y" | ufw reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing

    # 循环放行多个 SSH 端口，防止自锁
    IFS=',' read -r -a ssh_array <<< "$ssh_p"
    for p in "${ssh_array[@]}"; do
        ufw allow "$p"/tcp comment 'SSH_Lifeline' >/dev/null 2>&1
    done

    echo "y" | ufw enable >/dev/null 2>&1

    # 3. 配置 Fail2ban (接管 UFW)
    # backend 回退：journal 不可用时改用 auth.log，避免抓不到登录失败
    local fb_backend="systemd"
    local fb_logpath=""
    if ! journalctl -u ssh -n 1 >/dev/null 2>&1 && ! journalctl -u sshd -n 1 >/dev/null 2>&1; then
        fb_backend="auto"
        fb_logpath="logpath  = /var/log/auth.log"
    fi

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
backend = $fb_backend
$fb_logpath
EOF

    # 4. 启动服务 (必须在 UFW 启动后重启 fail2ban，确保链表正确注入)
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban

    module_state_mark_done "ufw"
    echo -e "${gl_lv}✔ 初始化完成！UFW & Fail2ban 已成功接管系统防御。${gl_bai}"
    echo -e "${gl_hui}Fail2ban 日志后端: ${fb_backend}${gl_bai}"
    sleep 2
}

# =================================================================
# [UI 面板] 交互式防火墙管理
# =================================================================
ufw_management() {
    # 检查并静默安装 UFW (防止未初始化时报错)
    if ! command -v ufw &> /dev/null; then
        echo -e "${gl_huang}>>> 尚未安装 UFW 核心组件，准备静默安装...${gl_bai}"
        apt update -y >/dev/null 2>&1 && apt install -y ufw >/dev/null 2>&1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#         高阶防火墙与流量调度中心 (UFW版)       #"
        echo -e "################################################${gl_bai}"
        
        local ufw_status=$(ufw status | grep -w "Status: active")

        local fw_badge
        if module_state_is_done "ufw"; then
            fw_badge="${gl_lv}● 已初始化${gl_bai} (${gl_hui}$(module_state_last_run "ufw")${gl_bai})"
        else
            fw_badge="${gl_huang}○ 未初始化${gl_bai}"
        fi
        echo -e "配置状态:     ${fw_badge}"

        if [ -n "$ufw_status" ]; then
            echo -e "底层引擎: ${gl_lv}UFW Active [✔ 已接管]${gl_bai}"
            echo -e "防爆破层: ${gl_lv}Fail2ban [✔ 已联动]${gl_bai}"
            echo -e "防自锁层: ${gl_lv}SSH Port(s) $(detect_ssh_port) [✔ 已保护]${gl_bai}"
            echo "------------------------------------------------"
            echo -e "${gl_kjlan}当前活动规则 (输入 3 可按序号删除):${gl_bai}"
            # 过滤掉 active 状态行，直接显示数字列表
            ufw status numbered | grep -v "Status: active"
            echo "------------------------------------------------"
            
            echo -e "${gl_lv} 1.${gl_bai} 添加 [全网放行] 端口"
            echo -e "${gl_lv} 2.${gl_bai} 添加 [定向 IP] 放行端口"
            echo -e "${gl_huang} 3.${gl_bai} 删除自定义放行规则 (按序号删除)"
            echo -e "------------------------------------------------"
            echo -e "${gl_kjlan} 4.${gl_bai} 查看 Fail2ban SSH 拦截黑名单"
            echo -e "${gl_hong} 8.${gl_bai} 彻底卸载防火墙 (恢复裸奔)"
        else
            echo -e " 当前状态: ${gl_hong}未初始化 (裸奔状态)${gl_bai}"
            echo -e " 核心逻辑: 无任何拦截，所有端口对外开放"
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
                    read -p "请输入放行端口 (支持端口段, 例: 80,443 或 50000:60000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口格式不合法！${gl_bai}"; sleep 2; continue
                    fi
                    
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto_input
                    # [修复] 逗号多端口和冒号端口段在未指定协议时会导致 UFW 语法错误，必须拆分执行
                    case "$proto_input" in
                        1|tcp) ufw allow "${VALIDATED_PORT}/tcp" >/dev/null 2>&1 ;;
                        2|udp) ufw allow "${VALIDATED_PORT}/udp" >/dev/null 2>&1 ;;
                        *) 
                            ufw allow "${VALIDATED_PORT}/tcp" >/dev/null 2>&1
                            ufw allow "${VALIDATED_PORT}/udp" >/dev/null 2>&1
                            ;;
                    esac
                    echo -e "${gl_lv}全局放行规则已添加并生效！${gl_bai}"
                    sleep 1
                fi
                ;;
            2)
                if [ -n "$ufw_status" ]; then
                    read -p "请输入白名单 IP 地址 (IPv4 或 IPv6): " ip
                    if ! validate_ip "$ip"; then
                        echo -e "${gl_hong}错误: 无效的 IP 地址格式！${gl_bai}"; sleep 2; continue
                    fi
                    
                    read -p "请输入定向放行端口 (例: 3306 或 1000:2000): " port
                    if ! validate_port "$port"; then
                        echo -e "${gl_hong}错误: 端口格式不合法！${gl_bai}"; sleep 2; continue
                    fi
                    
                    read -p "请选择协议 [ 1=tcp | 2=udp | 回车默认 both ]: " proto_input
                    case "$proto_input" in
                        1|tcp) ufw allow from "$ip" to any port "$VALIDATED_PORT" proto tcp >/dev/null 2>&1 ;;
                        2|udp) ufw allow from "$ip" to any port "$VALIDATED_PORT" proto udp >/dev/null 2>&1 ;;
                        *) 
                            ufw allow from "$ip" to any port "$VALIDATED_PORT" proto tcp >/dev/null 2>&1
                            ufw allow from "$ip" to any port "$VALIDATED_PORT" proto udp >/dev/null 2>&1
                            ;;
                    esac
                    echo -e "${gl_lv}定向放行规则已添加并生效！${gl_bai}"
                    sleep 1
                fi
                ;;
            3)
                if [ -n "$ufw_status" ]; then
                    echo -e "${gl_huang}提示: 请查看上方列表括号内的 [序号]${gl_bai}"
                    read -p "请输入要删除的规则序号 (纯数字): " num
                    if [[ "$num" =~ ^[0-9]+$ ]]; then
                        ufw --force delete "$num" >/dev/null 2>&1
                        echo -e "${gl_lv}规则 [$num] 已成功删除！${gl_bai}"
                        sleep 1
                    else
                        echo -e "${gl_hong}错误: 无效的序号格式！${gl_bai}"
                        sleep 1
                    fi
                fi
                ;;
            4)
                if [ -n "$ufw_status" ]; then
                    clear
                    echo -e "${gl_kjlan}=== Fail2ban 实时拦截状态 (sshd) ===${gl_bai}"
                    if command -v fail2ban-client &> /dev/null; then
                        fail2ban-client status sshd
                    else
                        echo -e "${gl_hong}未检测到 fail2ban 运行。${gl_bai}"
                    fi
                    echo -e "\n${gl_hui}提示: 若要解封某个 IP，可使用命令: fail2ban-client set sshd unbanip <IP>${gl_bai}"
                    echo -e "\n按任意键返回..."
                    read -n 1 -s
                fi
                ;;
            8) 
                if [ -n "$ufw_status" ]; then
                    echo -e "${gl_hong}警告: 这将清空所有放行规则、关闭防火墙，并停止防爆破引擎！${gl_bai}"
                    read -p "确定要彻底卸载吗？(y/n): " confirm
                    if [[ "$confirm" == "y" ]]; then
                        echo "y" | ufw reset >/dev/null 2>&1
                        ufw disable >/dev/null 2>&1
                        systemctl stop fail2ban >/dev/null 2>&1
                        systemctl disable fail2ban >/dev/null 2>&1
                        module_state_clear "ufw"
                        echo -e "${gl_lv}所有防御设施已撤离，系统回归开放状态。${gl_bai}"
                        sleep 2
                    fi
                fi
                ;;
            0) return ;;
            *) echo -e "${gl_hong}无效选项，请重新输入。${gl_bai}"; sleep 1 ;;
        esac
    done
}
