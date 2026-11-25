#!/bin/bash

# =========================================================
#  模块: proxy/singbox.sh
#  功能: Sing-box 安装 / 卸载（配置功能已移除，待后续自定义）
# =========================================================

singbox_management() {
    BIN_PATH="/usr/bin/sing-box"
    CONF_DIR="/etc/sing-box"

    get_ver() {
        local tag=$(curl -sL --max-time 5 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
        [ -z "$tag" ] && echo "v1.12.13" || echo "$tag"
    }

    install_sb() {
        echo -e "${gl_huang}检查架构...${gl_bai}"
        local arch=$(uname -m); local sb_arch=""
        case "$arch" in x86_64) sb_arch="amd64";; aarch64) sb_arch="arm64";; *) echo "不支持"; return;; esac

        local version=$(get_ver)
        echo -e "最新版本: ${gl_lv}${version}${gl_bai}"
        local ver_num=${version#v}
        local url="https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box_${ver_num}_linux_${sb_arch}.deb"

        echo -e "${gl_kjlan}下载 .deb...${gl_bai}"
        if curl -fL -o /tmp/sb.deb "$url"; then
            echo -e "${gl_huang}安装/升级...${gl_bai}"
            if command -v sing-box &>/dev/null; then
                ar x /tmp/sb.deb data.tar.xz --output /tmp/
                tar -xf /tmp/data.tar.xz -C /tmp/ ./usr/bin/sing-box
                systemctl stop sing-box
                cp -f /tmp/usr/bin/sing-box /usr/bin/sing-box; chmod +x /usr/bin/sing-box
                systemctl restart sing-box
                rm -f /tmp/sb.deb /tmp/data.tar.xz /tmp/usr/bin/sing-box; rm -rf /tmp/usr
                echo -e "${gl_lv}升级完成${gl_bai}"
            else
                apt install /tmp/sb.deb -y; rm -f /tmp/sb.deb
                systemctl daemon-reload; systemctl enable sing-box; systemctl restart sing-box 2>/dev/null
                echo -e "${gl_lv}安装完成${gl_bai}"
            fi
            sing-box version | head -n 1
        else
            echo -e "${gl_hong}下载失败${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    uninstall_sb() {
        echo -e "${gl_hong}警告: 将删除 Sing-box 程序及配置！${gl_bai}"
        read -p "确认? (y/n): " c
        if [[ "$c" == "y" ]]; then
            systemctl stop sing-box
            apt purge sing-box -y
            apt autoremove -y
            rm -rf "$CONF_DIR" /usr/bin/sing-box
            echo -e "${gl_lv}已卸载${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#          Sing-box 核心管理 (安装 / 卸载)      #"
        echo -e "################################################${gl_bai}"
        if systemctl is-active --quiet sing-box; then
            local v=$($BIN_PATH version 2>/dev/null | head -n 1 | awk '{print $3}')
            echo -e "状态: ${gl_lv}● 运行中${gl_bai} (Ver: ${v:-未知})"
        else
            echo -e "状态: ${gl_hong}● 已停止${gl_bai}"
        fi
        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 安装/升级 (Install Latest)"
        echo -e "------------------------------------------------"
        echo -e "${gl_hong} 9.${gl_bai} 彻底卸载 (Uninstall)"
        echo -e "${gl_hui} 0.${gl_bai} 返回上级菜单"
        echo -e "------------------------------------------------"
        read -p "选项: " c
        case "$c" in
            1) install_sb ;;
            9) uninstall_sb ;;
            0) return ;;
            *) echo "无效选项" ;;
        esac
    done
}
