#!/bin/bash

set -e

USER_NAME="$1"
BASE_DIR="/home/devops/k8s-users"
USER_DIR="${BASE_DIR}/${USER_NAME}"
API_SERVER="https://k8s-api.cluster.local:6443"

if [[ -z "$USER_NAME" ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

echo "=== Step 1: Prepare directories ==="
mkdir -p "$USER_DIR"
chmod 700 "$USER_DIR"

echo "=== Step 2: Generate Key + CSR ==="
openssl genrsa -out "${USER_DIR}/${USER_NAME}.key" 2048

openssl req -new \
    -key "${USER_DIR}/${USER_NAME}.key" \
    -out "${USER_DIR}/${USER_NAME}.csr" \
    -subj "/CN=${USER_NAME}"

echo "=== Step 3: Generate CSR YAML ==="
CSR_DATA=$(cat "${USER_DIR}/${USER_NAME}.csr" | base64 | tr -d "\n")

cat <<EOF > "${USER_DIR}/${USER_NAME}-csr.yaml"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}
spec:
  request: ${CSR_DATA}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

echo "=== Step 4: Apply CSR ==="
kubectl apply -f "${USER_DIR}/${USER_NAME}-csr.yaml" --validate=false
sleep 2

echo "=== Step 5: Approve CSR ==="
kubectl certificate approve "${USER_NAME}"
sleep 2

echo "=== Step 6: Extract certificate ==="
kubectl get csr "${USER_NAME}" \
  -o jsonpath='{.status.certificate}' \
  | base64 -d > "${USER_DIR}/${USER_NAME}.crt"

echo "=== Step 7: Create kubeconfig ==="
kubectl config set-cluster kubernetes \
  --server="${API_SERVER}" \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --kubeconfig="${USER_DIR}/${USER_NAME}.kubeconfig"

kubectl config set-credentials "${USER_NAME}" \
  --client-certificate="${USER_DIR}/${USER_NAME}.crt" \
  --client-key="${USER_DIR}/${USER_NAME}.key" \
  --embed-certs=true \
  --kubeconfig="${USER_DIR}/${USER_NAME}.kubeconfig"

kubectl config set-context "${USER_NAME}-context" \
  --cluster=kubernetes \
  --user="${USER_NAME}" \
  --kubeconfig="${USER_DIR}/${USER_NAME}.kubeconfig"

kubectl config use-context "${USER_NAME}-context" \
  --kubeconfig="${USER_DIR}/${USER_NAME}.kubeconfig"

echo "=== Step 8: Grant RBAC (Cluster admin) ==="
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USER_NAME}-cluster-admin
subjects:
- kind: User
  name: ${USER_NAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "===================================="
echo "User created successfully!"
echo "Folder: $USER_DIR"
echo "Kubeconfig: $USER_DIR/${USER_NAME}.kubeconfig"
echo "Export command:"
echo "  export KUBECONFIG=$USER_DIR/${USER_NAME}.kubeconfig"
echo "===================================="

