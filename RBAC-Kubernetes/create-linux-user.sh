#!/bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <linux-username>"
    exit 1
fi

LINUX_USER="$1"
OUTPUT_DIR="/home/$LINUX_USER/.kube"

echo "=== Step 1: Ensure Linux user exists ==="
if ! id "$LINUX_USER" &>/dev/null; then
    echo "Creating Linux user: $LINUX_USER"
    useradd -m -s /bin/bash "$LINUX_USER"

    echo "Set password for $LINUX_USER:"
    passwd "$LINUX_USER"
else
    echo "Linux user $LINUX_USER already exists"
fi

echo "=== Step 2: Prepare .kube directory ==="
mkdir -p "$OUTPUT_DIR"
chown $LINUX_USER:$LINUX_USER "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

echo "===================================="
echo "Linux user setup complete"
echo "Home directory: /home/$LINUX_USER"
echo ".kube directory: $OUTPUT_DIR"
echo "===================================="

