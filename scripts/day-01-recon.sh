#!/usr/bin/env bash
# ==============================================================================
# jiopc-vps-experiment / Day 1: Infrastructure Reconnaissance Runner
# ==============================================================================
# This script executes the read-only reconnaissance checks used during Day 1
# of the JioPC VPS empirical evaluation.
#
# Usage:
#   chmod +x day-01-recon.sh
#   ./day-01-recon.sh
# ==============================================================================

set -euo pipefail

LOG_FILE="day-01-recon-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "========================================================"
echo " JioPC VPS Experiment: Day 1 Infrastructure Reconnaissance"
echo " Date: $(date -u)"
echo "========================================================"

echo -e "\n[1/8] Identity & Permissions"
echo "--------------------------------------------------------"
whoami
id
pwd
if sudo -n true 2>/dev/null; then
    echo "[!] sudo: Passwordless sudo is available"
else
    echo "[*] sudo: Passwordless sudo not available (expected non-root)"
fi

echo -e "\n[2/8] Host Kernel & System Identification"
echo "--------------------------------------------------------"
uname -a
if [ -f /etc/os-release ]; then
    cat /etc/os-release | grep -E '^(NAME|VERSION)='
fi

echo -e "\n[3/8] Compute Subsystem (CPU & Instruction Sets)"
echo "--------------------------------------------------------"
lscpu | grep -E '(Model name|Socket|Thread|Core|CPU\(s\)|L3 cache|Hypervisor|Virtualization)' || true
echo "Vector Flag Support:"
lscpu | grep -i flags | grep -o -E '\b(avx|avx2|avx512[a-z0-9_]*|vnni)\b' | sort -u | tr '\n' ' '
echo ""

echo -e "\n[4/8] Memory & Swap Allocation"
echo "--------------------------------------------------------"
free -h

echo -e "\n[5/8] Storage Layout & Filesystem Capacity"
echo "--------------------------------------------------------"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
echo ""
df -hT

echo -e "\n[6/8] NFS Mount Parameters"
echo "--------------------------------------------------------"
mount | grep '/home' || echo "No /home mount detected via grep"

echo -e "\n[7/8] Network Interfaces & Routing"
echo "--------------------------------------------------------"
ip -br addr
echo ""
ip route

echo -e "\n[8/8] Proxy Environment & Outbound HTTP/HTTPS Check"
echo "--------------------------------------------------------"
env | grep -i proxy || echo "No proxy variables set"
echo ""
echo "Probing outbound HTTPS via proxy..."
curl -I --connect-timeout 5 https://example.com | head -n 10 || echo "curl to example.com failed"
echo ""
echo "Querying public egress IP..."
curl -4 -s --connect-timeout 5 https://ifconfig.me || echo "Could not query public IP"
echo ""

echo -e "\n[Audit] Listening Sockets"
echo "--------------------------------------------------------"
ss -tuln

echo -e "\n========================================================"
echo " Reconnaissance complete. Output saved to: ${LOG_FILE}"
echo "========================================================"
