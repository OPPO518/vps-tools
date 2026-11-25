#!/bin/bash

# =========================================================
#  模块: proxy/xray.sh
#  功能: Xray 安装 / 卸载（配置功能已移除，待后续自定义）
# =========================================================

xray_management() {
    BIN_PATH="/usr/local/bin/xray"
    CONF_DIR="/usr/local/etc/xray"

    install_xray() {
        echo -e "${gl_huang}正在调用官方脚本安装 (User=root)...${gl_bai}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        if [ $? -eq 0 ]; then
            echo -e "${gl_lv}安装/升级成功！${gl_bai}"
            $BIN_PATH version | head -n 1
        else
            echo -e "${gl_hong}安装失败！${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    uninstall_xray() {
        echo -e "${gl_hong}警告: 这将删除 Xray 程序、配置及日志！${gl_bai}"
        read -p "确认卸载? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
            rm -rf "$CONF_DIR"
            echo -e "${gl_lv}Xray 已彻底卸载。${gl_bai}"
        fi
        read -p "按回车继续..."
    }

    while true; do
        clear
        echo -e "${gl_kjlan}################################################"
        echo -e "#         Xray 核心管理 (安装 / 卸载)           #"
        echo -e "################################################${gl_bai}"
        if systemctl is-active --quiet xray; then
            local ver=$($BIN_PATH version 2>/dev/null | head -n 1 | awk '{print $2}')
            echo -e "状态: ${gl_lv}● 运行中${gl_bai} (Ver: ${ver:-未知})"
        else
            echo -e "状态: ${gl_hong}● 已停止 / 未安装${gl_bai}"
        fi

        echo -e "------------------------------------------------"
        echo -e "${gl_lv} 1.${gl_bai} 安装/更新 (Install Latest)"
        echo -e "------------------------------------------------"
        echo -e "${gl_hong} 9.${gl_bai} 彻底卸载 (Uninstall)"
        echo -e "${gl_hui} 0.${gl_bai} 返回上级菜单"
        echo -e "------------------------------------------------"
        read -p "请输入选项: " c
        case "$c" in
            1) install_xray ;;
            9) uninstall_xray ;;
            0) return ;;
            *) echo "无效选项" ;;
        esac
    done
}
