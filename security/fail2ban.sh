# [防失联进阶] 动态获取真实 SSH 端口
detect_ssh_port() {
    local ports=$(sshd -T 2>/dev/null | grep -i '^port ' | awk '{print $2}' | paste -sd "," -)
    echo "${ports:-22}"
}

init_ufw_fail2ban() {
    echo -e "${gl_huang}>>> 正在初始化 UFW & Fail2ban 安全矩阵...${gl_bai}"
    
    # 1. 安装核心组件 (不再强制依赖 rsyslog，拥抱 systemd)
    apt update -y >/dev/null 2>&1
    apt install -y ufw fail2ban >/dev/null 2>&1

    # 2. 获取当前 SSH 端口，防止 UFW 把自己关在门外
    local ssh_p=$(detect_ssh_port)
    
    # 3. 初始化 UFW 基本盘
    echo "y" | ufw reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    
    # 循环放行多个 SSH 端口 (如果存在)
    IFS=',' read -r -a ssh_array <<< "$ssh_p"
    for p in "${ssh_array[@]}"; do
        ufw allow "$p"/tcp comment 'SSH_Lifeline'
    done
    
    # 强制启用 UFW
    echo "y" | ufw enable >/dev/null 2>&1

    # 4. 配置 Fail2ban (完美适配 UFW 环境)
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# 永远不封禁本机、内网和特定的白名单 IP
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
# 封禁时间：1天 (86400秒)
bantime  = 86400
# 统计窗口：10分钟
findtime = 600
# 容错次数：3次
maxretry = 3
# 【核心修改】将拦截动作移交给 UFW
banaction = ufw

[sshd]
enabled = true
port    = $ssh_p
# 【核心修改】现代 Linux 直接读取 systemd 日志，抛弃 auth.log
backend = systemd
EOF

    # 5. 重启 Fail2ban 生效
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    
    echo -e "${gl_lv}✔ UFW & Fail2ban 已成功接管系统防御！${gl_bai}"
    echo -e "${gl_hui}当前 SSH 端口 (${ssh_p}) 已自动放入 UFW 白名单。${gl_bai}"
}
