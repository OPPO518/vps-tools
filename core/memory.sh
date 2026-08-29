# ==========================================
#  内存管理模块 (ZRAM + 智能 Swapfile) [终极进化版]
# ==========================================

swap_management() {
    while true; do
        clear
        # 尝试唤醒 ZRAM 内核模块 (防精简系统未加载)
        modprobe zram 2>/dev/null
        
        # --- [状态采集逻辑] ---
        local total_mem=$(free -m | awk '/^Mem:/{print $2}')
        local swap_total=$(free -m | grep Swap | awk '{print $2}')
        local zram_status=$(lsmod | grep -q zram && echo -e "${gl_lv}● 已启用${gl_bai}" || echo -e "${gl_hong}○ 未启用/不支持${gl_bai}")
        local trim_timer=$(systemctl is-active fstrim.timer 2>/dev/null | grep -q "active" && echo -e "${gl_lv}已开启(每周)${gl_bai}" || echo -e "${gl_huang}未开启${gl_bai}")
        local trim_check=$(lsblk -nd -o DISC-MAX 2>/dev/null | awk '$1 != "0B" {print $1}' | head -n 1)
        local trim_support=$( [ -n "$trim_check" ] && echo -e "${gl_lv}支持${gl_bai}" || echo -e "${gl_huang}未知/不支持${gl_bai}" )

        # --- 渲染新版 UI ---
        echo -e "${gl_kjlan}╭────────────────────────────────────────────────────────────────╮${gl_bai}"
        echo -e "${gl_kjlan}│${gl_bai}                VPS 进阶内存调度与 ZRAM 优化中心                ${gl_kjlan}│${gl_bai}"
        echo -e "${gl_kjlan}╰────────────────────────────────────────────────────────────────╯${gl_bai}"
        echo -e " 内存调度状态: ${zram_status}"
        echo -e " 物理内存总量: ${gl_bai}${total_mem} MB${gl_bai}  |  当前交换总量: ${gl_bai}${swap_total} MB${gl_bai}"
        echo -e " 自动 Trim:    ${trim_timer}  |  硬件 Trim 支持: ${trim_support}"
        echo -e "${gl_kjlan}------------------------------------------------------------------${gl_bai}"
        
        echo -e " ${gl_huang}[ ⚡ 自动化优化策略 ]${gl_bai}"
        echo -e "   ${gl_lv}1.${gl_bai} 一键部署/更新 智能内存优化 (推荐)      ${gl_lv}[智能分级策略]${gl_bai}"
        echo -e "   ${gl_hong}2.${gl_bai} 彻底卸载 ZRAM 与 Swapfile 逻辑"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e " ${gl_huang}[ 🔍 实时状态感知 ]${gl_bai}"
        echo -e "   ${gl_kjlan}3.${gl_bai} 深度查看交换详情 (zramctl/swapon)"
        echo -e "   ${gl_kjlan}4.${gl_bai} 尝试执行手动 SSD Trim 优化"
        
        echo -e " ${gl_hui}┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈${gl_bai}"
        
        echo -e "   ${gl_hui}0. 返回上级菜单 (Back)${gl_bai}"
        echo -e "${gl_kjlan}==================================================================${gl_bai}"
        
        read -p " 请输入选项 [0-4]: " choice
        
        case "$choice" in
            1)
                echo -e "${gl_huang}>>> 正在分析机器配置并部署进阶内存优化方案...${gl_bai}"
                
                # --- 1. 环境净化与静默安装 (防 Ubuntu 弹窗卡死) ---
                export DEBIAN_FRONTEND=noninteractive
                export NEEDRESTART_MODE=a
                export NEEDRESTART_SUSPEND=1
                
                apt update -y >/dev/null 2>&1
                apt install -y zram-tools >/dev/null 2>&1
                
                # 卸载旧的 swapfile 释放空间
                swapoff -a 2>/dev/null
                rm -f /swapfile
                sed -i '/swapfile/d' /etc/fstab

                # --- 2. 核心调度大脑：动态智能判定模块 ---
                local z_percent
                local swap_size=0
                local swappiness
                local cache_pressure=100

                if [ "$total_mem" -le 1024 ]; then
                    # Tier 1: 极小内存架构 (<= 1GB)
                    echo -e "${gl_huang}[策略] 判定为极小内存架构，启用 生存保命模式...${gl_bai}"
                    z_percent=100
                    swap_size=$((total_mem * 2))
                    [ "$swap_size" -gt 2048 ] && swap_size=2048 # 最高封顶2G
                    swappiness=85
                elif [ "$total_mem" -lt 6144 ]; then
                    # Tier 2: 主流内存架构 (1GB ~ 6GB)
                    echo -e "${gl_lv}[策略] 判定为主流内存架构，启用 性能均衡模式...${gl_bai}"
                    z_percent=50
                    swap_size=2048
                    swappiness=60
                else
                    # Tier 3: 大内存架构 (>= 6GB)
                    echo -e "${gl_kjlan}[策略] 判定为大内存架构，启用 极致缓存模式...${gl_bai}"
                    z_percent=25
                    swap_size=0       # 彻底禁用磁盘Swap
                    swappiness=10
                    cache_pressure=50 # 积极保留系统文件缓存
                fi

                # --- 3. 配置 ZRAM (第一道防线) ---
                cat > /etc/default/zramswap << EOF
ALGO=zstd
PERCENT=$z_percent
PRIORITY=100
EOF
                systemctl restart zramswap

                # --- 4. 磁盘 I/O 测速与 Swapfile 部署 ---
                if [ "$swap_size" -gt 0 ]; then
                    echo -e "${gl_kjlan}>>> 正在探测磁盘底层真实 I/O (物理直写防抖测速)...${gl_bai}"
                    
                    local start_time=$(date +%s%N)
                    dd if=/dev/zero of=/root/test_io_temp bs=1M count=100 oflag=direct >/dev/null 2>&1
                    local end_time=$(date +%s%N)
                    rm -f /root/test_io_temp
                    
                    local time_diff=$(( (end_time - start_time) / 1000000 ))
                    [ "$time_diff" -eq 0 ] && time_diff=1
                    local speed_mbps=$(( 100000 / time_diff ))
                    
                    echo -e " > 磁盘直写检测值: ${gl_kjlan}${speed_mbps} MB/s${gl_bai}"

                    if [ "$speed_mbps" -lt 40 ]; then
                        echo -e "${gl_hong}[警告] 检测到磁盘底层真实 I/O 极差 (石头盘)！已触发保护机制，取消 Swapfile 创建以防系统死锁。${gl_bai}"
                    else
                        echo -e "${gl_lv} > 磁盘状态良好，正在创建 ${swap_size}MB 物理安全气囊...${gl_bai}"
                        
                        # [防错机制] 针对 BTRFS 系统的写时复制(CoW)拦截
                        if df -T / | grep -q "btrfs"; then
                            touch /swapfile
                            chattr +C /swapfile 2>/dev/null
                        fi

                        dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
                        chmod 600 /swapfile
                        mkswap /swapfile
                        swapon --priority -2 /swapfile
                        echo '/swapfile none swap sw,pri=-2 0 0' >> /etc/fstab
                    fi
                else
                    echo -e "${gl_lv}[策略] 当前配置充足，已自动跳过 Swapfile 创建。${gl_bai}"
                fi

                # --- 5. 系统内核参数深度调优 ---
                cat > /etc/sysctl.d/90-memory-tune.conf << EOF
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$cache_pressure
EOF
                sysctl -p /etc/sysctl.d/90-memory-tune.conf >/dev/null

                # --- 6. 开启 SSD 自动垃圾回收机制 (Trim) ---
                systemctl enable --now fstrim.timer >/dev/null 2>&1
                
                echo -e "\n${gl_lv}🎉 部署完成！全局智能内存调度策略已生效。${gl_bai}"
                read -p "按回车继续..."
                ;;
                
            2)
                echo -e "${gl_huang}正在彻底回滚内存配置...${gl_bai}"
                swapoff -a 2>/dev/null
                systemctl stop zramswap 2>/dev/null
                
                export DEBIAN_FRONTEND=noninteractive
                apt purge -y zram-tools >/dev/null 2>&1
                
                rm -f /swapfile /etc/sysctl.d/90-memory-tune.conf /root/test_io_temp
                sed -i '/swapfile/d' /etc/fstab
                # 重新应用默认 sysctl 参数
                sysctl --system >/dev/null 2>&1 
                
                echo -e "${gl_lv}✅ 卸载完成，内存配置已恢复原生状态。${gl_bai}"
                read -p "按回车继续..."
                ;;
                
            3)
                clear
                echo -e "${gl_kjlan}=== ZRAM 压缩详情 ===${gl_bai}"
                zramctl 2>/dev/null || echo -e "${gl_hong}ZRAM 未启用或模块未加载${gl_bai}"
                
                echo -e "\n${gl_kjlan}=== 交换层优先级 (Priority 越大越优先) ===${gl_bai}"
                swapon --show
                read -p "按回车继续..."
                ;;
                
            4)
                echo -e "${gl_huang}正在向 SSD 硬件发送闲置区块回收指令 (Trim)...${gl_bai}"
                if fstrim -v /; then
                    echo -e "${gl_lv}✅ Trim 优化执行成功！${gl_bai}"
                else
                    echo -e "${gl_hong}❌ 执行失败，当前磁盘环境可能不支持 Trim。${gl_bai}"
                fi
                read -p "按回车继续..."
                ;;
                
            0) 
                return 
                ;;
                
            *) 
                echo -e "${gl_hong}无效选项，请输入 0-4${gl_bai}"
                sleep 1 
                ;;
        esac
    done
}
