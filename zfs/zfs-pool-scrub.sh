#!/bin/bash
# High-Capacity OpenZFS Data Scrub Controller
set -euo pipefail

POOL_NAME="storage-pool"
LOG_FILE="/var/log/zfs-scrub-engine.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initializing scheduled data scrub check..." >> "$LOG_FILE"

# 1. Verify if an active scrub sequence is already running on the target array
if zpool status "${POOL_NAME}" | grep -q "scrub in progress"; then
    echo "[*] A data scrub loop is already executing on ${POOL_NAME}. Terminating duplicate task." >> "$LOG_FILE"
    exit 0
fi

# 2. Dynamic Performance Tuning: Lower scrub priority to safeguard racing I/O bandwidth
# This instructs the OpenZFS kernel module to yield to real-time client data streams
sysctl -w vfs.zfs.scrub_delay=4 >> "$LOG_FILE" 2>&1 || true
sysctl -w vfs.zfs.top_maxinflight=32 >> "$LOG_FILE" 2>&1 || true

# 3. Fire the OpenZFS Native Scan Engine
zpool scrub "${POOL_NAME}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ZFS data scrub triggered successfully for ${POOL_NAME}." >> "$LOG_FILE"