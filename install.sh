#!/bin/bash
#
# GPU Auto-Shutdown - Install Script
# Usage: sudo ./install.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo ./install.sh"
    exit 1
fi

case "${1:---install}" in
    --uninstall)
        echo "Uninstalling..."
        systemctl stop gpu-monitor 2>/dev/null || true
        systemctl disable gpu-monitor 2>/dev/null || true
        rm -f /usr/local/bin/gpu-monitor.sh
        rm -f /etc/systemd/system/gpu-monitor.service
        systemctl daemon-reload
        echo "Done"
        ;;
    --install|*)
        echo "Installing GPU Auto-Shutdown..."
        
        # Check nvidia-smi
        if ! command -v nvidia-smi &>/dev/null; then
            echo "Warning: nvidia-smi not found. Service needs NVIDIA GPU."
        fi
        
        # Install
        cp "$SCRIPT_DIR/gpu-monitor.sh" /usr/local/bin/
        chmod +x /usr/local/bin/gpu-monitor.sh
        cp "$SCRIPT_DIR/gpu-monitor.service" /etc/systemd/system/
        
        # Enable & start
        systemctl daemon-reload
        systemctl enable gpu-monitor
        systemctl start gpu-monitor
        
        echo ""
        echo "Installed! Commands:"
        echo "  View logs:    journalctl -u gpu-monitor -f"
        echo "  Status:       systemctl status gpu-monitor"
        echo "  Stop:         sudo systemctl stop gpu-monitor"
        echo "  Configure:    sudo nano /etc/systemd/system/gpu-monitor.service"
        echo "  Uninstall:    sudo ./install.sh --uninstall"
        ;;
esac
