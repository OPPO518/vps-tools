system_initialize() {
    clear
    echo -e "${gl_kjlan}################################################"
    echo -e "#    系统初始化、时钟同步与网络调优 (Debian/Ubuntu)    #"
    echo -e "################################################${gl_bai}"
    
    # --- 1. 系统版本严格校验与源配置 ---
    if [ ! -f /etc/os-release ]; then
        echo -e "${gl_hong}错误: 找不到 /etc/os-release，无法识别系统类型！${gl_bai}"
        read -p "按回车返回..."
        return
    fi

    # 获取系统信息
    . /etc/os-release
    local os_id="${ID}"
    local os_ver_major="${VERSION_ID%%.*}"
    local os_codename="${VERSION_CODENAME}"

    # 验证系统支持范围并提示
    if [[ "$os_id" == "debian" && "$os_ver_major" -ge 10 ]]; then
        echo -e "当前系统: ${gl_huang}Debian $VERSION_ID ($os_codename)${gl_bai}"
    elif [[ "$os_id" == "ubuntu" && "$os_ver_major" -ge 20 ]]; then
        echo -e "当前系统: ${gl_huang}Ubuntu $VERSION_ID ($os_codename)${gl_bai}"
    else
        echo -e "${gl_hong}错误: 本模块仅支持 Debian 10+ 或 Ubuntu 20.04+ 系统！${gl_bai}"
        read -p "按回车返回..."
        return
    fi

    echo -e "${gl_kjlan}>>> 正在配置官方/归档源...${gl_bai}"
    # 备份传统源
    [ -f /etc/apt/sources.list ] && cp /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%F)

    # 动态构建软件源
    if [[ "$os_id" == "debian" ]]; then
        if [ "$os_ver_major" == "10" ]; then
            # Debian 10 归档源处理
            echo -e "deb http://archive.debian.org/debian buster main contrib non-free\ndeb http://archive.debian.org/debian-security buster/updates main contrib non-free" > /etc/apt/sources.list
            echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
        else
            # Debian 11/12/13+ 动态适配
            local deb_comp="main contrib non-free"
            # Debian 12 (Bookworm) 及 13 (Trixie) 必须添加 non-free-firmware
            if [ "$os_ver_major" -ge 12 ]; then
                deb_comp="main contrib non-free non-free-firmware"
            fi
            
            cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ $os_codename $deb_comp
deb http://deb.debian.org/debian-security/ $os_codename-security $deb_comp
deb http://deb.debian.org/debian/ $os_codename-updates $deb_comp
deb http://deb.debian.org/debian/ $os_codename-backports $deb_comp
EOF
        fi
    elif [[ "$os_id" == "ubuntu" ]]; then
        if [ "$os_ver_major" -ge 24 ]; then
            # Ubuntu 24.04 / 26.04+ 采用全新的 DEB822 格式
            echo -e "${gl_huang}检测到 Ubuntu 24.04/26.04+，采用 DEB822 格式源配置...${gl_bai}"
            [ -f /etc/apt/sources.list.d/ubuntu.sources ] && cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak_$(date +%F)
            
            # 清空传统源，防止冲突报 warning
            > /etc/apt/sources.list
            
            cat > /etc/apt/sources.list.d/ubuntu.sources << EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: $os_codename $os_codename-updates $os_codename-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: $os_codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        else
            # Ubuntu 20.04 / 22.04 传统单行格式
            cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ $os_codename main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $os_codename-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $os_codename-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $os_codename-security main restricted universe multiverse
EOF
        fi
    fi

    # --- 2. 系统升级与工具安装 ---
    echo -e "${gl_kjlan}>>> 正在更新系统并安装基础组件...${gl_bai}"
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    apt update && apt upgrade -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" --ignore-missing
    apt install -y wget rsync socat chrony unzip

    # [系统优化] SSH 深度安全加固与稳定性优化
    optimize_ssh() {
        echo -e "${gl_kjlan}>>> 正在执行 SSH 深度安全加固与稳定性优化...${gl_bai}"
        local ssh_conf="/etc/ssh/sshd_config"
        
        [ ! -f "${ssh_conf}.bak" ] && cp "$ssh_conf" "${ssh_conf}.bak"

        sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 60/' "$ssh_conf"
        sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 5/' "$ssh_conf"
        sed -i 's/^#\?UseDNS.*/UseDNS no/' "$ssh_conf"
        sed -i 's/^#\?LoginGraceTime.*/LoginGraceTime 1m/' "$ssh_conf"
        sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$ssh_conf"
        sed -i 's/^#\?StrictModes.*/StrictModes yes/' "$ssh_conf"
        sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$ssh_conf"
        sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$ssh_conf"

        if sshd -t &>/dev/null; then
            systemctl restart sshd
        else
            echo -e "${gl_hong}错误: SSH 配置语法检查失败，已回退配置！${gl_bai}"
            cp "${ssh_conf}.bak" "$ssh_conf"
            systemctl restart sshd
        fi
    }
    
    optimize_ssh

    # --- 3. 时间同步与时区配置 (Chrony 高精度方案) ---
    echo -e "${gl_kjlan}>>> 正在配置时区与 Chrony 高可用同步源...${gl_bai}"
    timedatectl set-timezone Asia/Shanghai

    systemctl stop systemd-timesyncd 2>/dev/null
    systemctl mask systemd-timesyncd.service

    [ -f /etc/chrony/chrony.conf ] && cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
    sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
    sed -i 's/^server/#server/g' /etc/chrony/chrony.conf

    cat >> /etc/chrony/chrony.conf << EOF

# 自定义高可用 NTP 服务器 (Cloudflare + Google)
server time.cloudflare.com iburst
server time.google.com iburst
EOF

    systemctl enable --now chrony
    systemctl restart chrony

    # --- 4. 动态计算内存并分配 TCP 缓冲区 ---
    echo -e "${gl_kjlan}>>> 正在计算物理内存并分配 TCP 缓冲区...${gl_bai}"
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local buf_max="33554432" 
    
    if [ "$total_mem" -le 600 ]; then
        buf_max="8388608"
        echo -e "检测到极小内存 (${total_mem}MB)，采用保守缓冲区策略 (8MB)"
    elif [ "$total_mem" -le 2048 ]; then
        buf_max="33554432"
        echo -e "检测到标准内存 (${total_mem}MB)，采用均衡缓冲区策略 (32MB)"
    else
        buf_max="67108864"
        echo -e "检测到大容量内存 (${total_mem}MB)，采用激进缓冲区策略 (64MB)"
    fi

    # --- 5. 写入 TCP 深度调优与 BBR 配置 ---
    echo -e "${gl_kjlan}>>> 正在写入 TCP 深度调优与 BBR 配置...${gl_bai}"
    rm -f /etc/sysctl.d/99-vps-optimize.conf
    
    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
# ── BBR 拥塞控制 ──
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── 动态缓冲区分配 (${buf_max} 字节) ──
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = ${buf_max}
net.core.wmem_max = ${buf_max}
net.ipv4.tcp_rmem = 4096 87380 ${buf_max}
net.ipv4.tcp_wmem = 4096 65536 ${buf_max}
net.ipv4.tcp_mem = 786432 1048576 26777216

# ── TIME_WAIT 连接回收与复用 ──
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 20000

# ── 连接保活 (keepalive) ──
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# ── SYN 握手防洪 ──
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192

# ── 端口范围与 MTU 探测 ──
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_mtu_probing = 1

# ── 队列与 TCP 快速选项 ──
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 1

# ── 连接追踪表与防报错 ──
net.netfilter.nf_conntrack_max = 1000000
net.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# ── 提升文件描述符 ──
fs.file-max = 1000000
EOF

    if ! grep -q "# tcp-tune" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# tcp-tune: 提升文件描述符限制
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    fi

    sysctl --system 2>/dev/null | grep -v "nf_conntrack" >/dev/null

    # --- 6. 垃圾清理 ---
    echo -e "${gl_kjlan}>>> 正在清理系统缓存垃圾...${gl_bai}"
    apt autoremove -y && apt clean

    # --- 7. 初始化报告 ---
    echo -e "\n${gl_lv}====== 基建、网络优化与时钟同步已就绪 ======${gl_bai}"
    local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local cur_wmem=$(sysctl -n net.core.wmem_max 2>/dev/null)
    local wmem_mb=$((cur_wmem / 1024 / 1024))
    local fw_v4=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    local fw_v6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)
    
    echo -e " 1. BBR 拥塞控制: \t${gl_kjlan}${bbr_status}${gl_bai}"
    echo -e " 2. TCP 缓冲上限: \t${gl_kjlan}${wmem_mb} MB${gl_bai}"
    echo -e " 3. 系统网络转发: \t${gl_bai}v4->${fw_v4} v6->${fw_v6}${gl_bai}"
    echo -e " 4. 当前系统时间: \t${gl_bai}$(date "+%Y-%m-%d %H:%M:%S") (CST)${gl_bai}"
    echo -e "------------------------------------------------"
    echo -e "${gl_huang} Chrony 同步源状态 (chronyc sources -v):${gl_bai}"
    chronyc sources -v
    echo -e "------------------------------------------------"
    
    if [ -f /var/run/reboot-required ]; then
        echo -e "${gl_hong}!!! 检测到内核/组件更新，建议尽快重启 !!!${gl_bai}"
        read -p "是否立即重启? (y/n): " rb
        [[ "$rb" =~ ^[yY]$ ]] && reboot
    else
        read -p "按回车返回主菜单..."
    fi
}
