#!/bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USER_NAME="$1"

SRC_DIR="/home/devops/k8s-users/${USER_NAME}"
SRC_FILE="${SRC_DIR}/${USER_NAME}.kubeconfig"

DEST_DIR="/home/${USER_NAME}/.kube"
DEST_FILE="${DEST_DIR}/config"

echo "=== Step 1: Verify kubeconfig file exists ==="

if [[ ! -f "$SRC_FILE" ]]; then
    echo "ERROR: Source kubeconfig not found at: $SRC_FILE"
    exit 1
fi

echo "=== Step 2: Ensure destination .kube directory exists ==="
if [[ ! -d "$DEST_DIR" ]]; then
    echo "Creating $DEST_DIR ..."
    mkdir -p "$DEST_DIR"
    chown ${USER_NAME}:${USER_NAME} "$DEST_DIR"
    chmod 700 "$DEST_DIR"
fi

echo "=== Step 3: Moving kubeconfig ==="
mv "$SRC_FILE" "$DEST_FILE"

echo "=== Step 4: Fix permissions ==="
chown ${USER_NAME}:${USER_NAME} "$DEST_FILE"
chmod 600 "$DEST_FILE"

echo "==============================================="
echo " Kubeconfig moved successfully!"
echo " User: $USER_NAME"
echo " New path: $DEST_FILE"
echo "==============================================="

