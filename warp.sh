cat > /usr/local/bin/warp-manager.sh << 'EOF'
#!/bin/bash

# WARP Manager Script - Improved version
# Based on P3TERX/warp.sh with fixed status check logic

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查 WireGuard 接口状态
check_wg_interface() {
    if ip link show wgcf &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查 WARP 连接状态（等待握手完成）
check_warp_connection() {
    local max_wait=15
    local count=0
    
    print_info "Waiting for WARP handshake (max ${max_wait}s)..."
    
    while [ $count -lt $max_wait ]; do
        if wg show wgcf 2>/dev/null | grep -q "latest handshake"; then
            print_info "WARP handshake successful!"
            
            # 验证实际连接
            if timeout 5 curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"; then
                print_info "WARP connection verified!"
                return 0
            fi
        fi
        sleep 1
        ((count++))
    done
    
    print_error "WARP handshake timeout after ${max_wait}s"
    return 1
}

# 启动 WARP
start_warp() {
    print_info "Starting WireGuard..."
    
    # 检查是否已运行
    if check_wg_interface; then
        print_warning "WireGuard interface already exists"
        print_info "Checking connection status..."
        if wg show wgcf | grep -q "latest handshake"; then
            print_info "WireGuard is already running."
            return 0
        else
            print_warning "Interface exists but no handshake, restarting..."
            wg-quick down wgcf
        fi
    fi
    
    # 启动 WireGuard
    if systemctl start wg-quick@wgcf; then
        print_info "WireGuard service started."
    else
        print_error "Failed to start WireGuard service!"
        journalctl -xeu wg-quick@wgcf --no-pager -n 20
        return 1
    fi
    
    # 等待并检查连接
    if check_warp_connection; then
        print_info "WireGuard is running successfully."
        
        # 显示连接信息
        echo ""
        echo "========== Connection Info =========="
        curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E "ip=|warp=|loc="
        echo "====================================="
        echo ""
        
        return 0
    else
        print_error "WARP connection failed!"
        print_info "Checking logs..."
        journalctl -xeu wg-quick@wgcf --no-pager -n 20
        return 1
    fi
}

# 停止 WARP
stop_warp() {
    print_info "Stopping WireGuard..."
    
    if ! check_wg_interface; then
        print_warning "WireGuard is not running."
        return 0
    fi
    
    if systemctl stop wg-quick@wgcf; then
        print_info "WireGuard has been stopped."
        return 0
    else
        print_error "Failed to stop WireGuard!"
        return 1
    fi
}

# 重启 WARP
restart_warp() {
    print_info "Restarting WireGuard..."
    stop_warp
    sleep 2
    start_warp
}

# 查看状态
status_warp() {
    echo ""
    echo "========== WireGuard Status =========="
    
    if ! check_wg_interface; then
        print_warning "WireGuard is not running."
        return 1
    fi
    
    echo ""
    systemctl status wg-quick@wgcf --no-pager -l
    
    echo ""
    echo "========== WireGuard Interface =========="
    wg show wgcf
    
    echo ""
    echo "========== Connection Test =========="
    if timeout 5 curl -s https://www.cloudflare.com/cdn-cgi/trace; then
        echo ""
    else
        print_error "Connection test failed!"
    fi
    echo "======================================"
}

# 启用开机自启
enable_warp() {
    print_info "Enabling WireGuard on boot..."
    if systemctl enable wg-quick@wgcf; then
        print_info "WireGuard auto-start enabled."
    else
        print_error "Failed to enable auto-start!"
        return 1
    fi
}

# 禁用开机自启
disable_warp() {
    print_info "Disabling WireGuard on boot..."
    if systemctl disable wg-quick@wgcf; then
        print_info "WireGuard auto-start disabled."
    else
        print_error "Failed to disable auto-start!"
        return 1
    fi
}

# 卸载 WARP
uninstall_warp() {
    print_warning "This will remove WireGuard and WARP configuration."
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled."
        return 0
    fi
    
    print_info "Stopping WireGuard..."
    systemctl stop wg-quick@wgcf 2>/dev/null
    systemctl disable wg-quick@wgcf 2>/dev/null
    
    print_info "Removing configuration..."
    rm -f /etc/wireguard/wgcf.conf
    rm -f /usr/local/bin/wgcf
    rm -f /usr/local/bin/warp-manager.sh
    
    print_info "WARP has been uninstalled."
}

# 显示菜单
show_menu() {
    clear
    echo "======================================="
    echo "     WARP Manager (Improved)"
    echo "======================================="
    echo ""
    echo "1. Start WARP"
    echo "2. Stop WARP"
    echo "3. Restart WARP"
    echo "4. Status"
    echo "5. Enable auto-start"
    echo "6. Disable auto-start"
    echo "7. Uninstall"
    echo "0. Exit"
    echo ""
    echo "======================================="
}

# 主函数
main() {
    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        exit 1
    fi
    
    # 检查配置文件
    if [[ ! -f /etc/wireguard/wgcf.conf ]]; then
        print_error "WARP config not found at /etc/wireguard/wgcf.conf"
        print_info "Please install WARP first using: bash <(curl -fsSL git.io/warp.sh)"
        exit 1
    fi
    
    # 命令行参数处理
    case "$1" in
        start|s)
            start_warp
            ;;
        stop|p)
            stop_warp
            ;;
        restart|r)
            restart_warp
            ;;
        status|t)
            status_warp
            ;;
        enable|e)
            enable_warp
            ;;
        disable|d)
            disable_warp
            ;;
        uninstall|u)
            uninstall_warp
            ;;
        *)
            # 交互菜单
            while true; do
                show_menu
                read -p "Please select [0-7]: " choice
                
                case $choice in
                    1)
                        start_warp
                        read -p "Press Enter to continue..."
                        ;;
                    2)
                        stop_warp
                        read -p "Press Enter to continue..."
                        ;;
                    3)
                        restart_warp
                        read -p "Press Enter to continue..."
                        ;;
                    4)
                        status_warp
                        read -p "Press Enter to continue..."
                        ;;
                    5)
                        enable_warp
                        read -p "Press Enter to continue..."
                        ;;
                    6)
                        disable_warp
                        read -p "Press Enter to continue..."
                        ;;
                    7)
                        uninstall_warp
                        read -p "Press Enter to continue..."
                        ;;
                    0)
                        print_info "Goodbye!"
                        exit 0
                        ;;
                    *)
                        print_error "Invalid option!"
                        read -p "Press Enter to continue..."
                        ;;
                esac
            done
            ;;
    esac
}

main "$@"
EOF

# 设置执行权限
chmod +x /usr/local/bin/warp-manager.sh

# 创建快捷命令
ln -sf /usr/local/bin/warp-manager.sh /usr/local/bin/warp

echo -e "${GREEN}WARP Manager installed successfully!${NC}"
echo ""
echo "Usage:"
echo "  warp              - Interactive menu"
echo "  warp start        - Start WARP"
echo "  warp stop         - Stop WARP"
echo "  warp restart      - Restart WARP"
echo "  warp status       - Check status"
echo "  warp enable       - Enable auto-start"
echo "  warp disable      - Disable auto-start"