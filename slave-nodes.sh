echo ">>> kubeadm cluster setup start"

echo ">>> Editing /etc/hosts file"

LINES=(
  "10.10.2.39  stage.proxyhost.lan"
  "172.21.1.16  isu-k8s-wk-4"
)

for LINE in "${LINES[@]}"; do
  if grep -qF "$LINE" /etc/hosts; then
    echo "Entry already exists: $LINE"
  else
    echo "Adding entry: $LINE"
    echo "$LINE" | sudo tee -a /etc/hosts > /dev/null
  fi
done

echo ">>> /etc/hosts updated successfully"





echo ">>> Disable SELinux & Firewall and change SELINUX enforcing to permissive"

sudo setenforce 0

if grep -q '^SELINUX=enforcing' /etc/selinux/config; then
    echo "Changing SELINUX from enforcing to permissive..."
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    echo "SELINUX set to permissive"
else
    echo "SELINUX is not set to enforcing (no change needed)"
fi


echo ">>>  Installing Firewalld serivice"

sudo dnf install firewalld -y
sudo systemctl enable --now firewalld


if systemctl list-unit-files | grep -q firewalld.service; then
    sudo systemctl disable --now firewalld
    echo "Firewalld disabled"
else
    echo "Firewalld not installed, Skipping..."
fi



echo ">>> Disable Swap"

sudo swapoff -a

if grep -qE '^\s*[^#].*\sswap\s' /etc/fstab; then
    echo "Disabling swap in /etc/fstab..."
    sudo sed -i '/ swap / s/^/#/' /etc/fstab
    echo "Swap disabled"
else
    echo "Swap already disabled or not present"
fi


echo ">>> Configure sysctl params (Networking)"

if [ ! -f /etc/modules-load.d/k8s.conf ]; then
    echo "Creating /etc/modules-load.d/k8s.conf..."
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
br_netfilter
overlay
EOF
else
    echo "File already exists"
fi

sudo modprobe overlay
sudo modprobe br_netfilter


if [ ! -f /etc/sysctl.d/k8s.conf ]; then
    echo "Creating /etc/sysctl.d/k8s.conf..."
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
else
    echo "File already exists"
fi



sudo sysctl --system




echo ">>> Installing kubeadm, kubelet, kubectl package"

KUBERNETES_VERSION=v1.35



sudo dnf update

sudo dnf install -y curl gnupg2 ca-certificates


cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF


sudo dnf update

sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes




echo ">>> Package installation complete"

sleep 3
echo "Continuing after 3 seconds"

sudo systemctl enable --now kubelet

echo ">>> Edit the file to set ulimit in kubernetes files"

if grep -q "^LimitNOFILE=" /usr/lib/systemd/system/kubelet.service; then
    echo "LimitNOFILE already set in kubelet.service"
else
    echo "Adding LimitNOFILE to kubelet.service..."
    sudo sed -i '/RestartSec=10/a LimitNOFILE=65000' /usr/lib/systemd/system/kubelet.service
    echo "LimitNOFILE added"
fi


sudo systemctl daemon-reexec
sudo systemctl restart kubelet


sleep 5
echo "Continuing after 5 seconds"


echo "==== Kubernetes Node Checks ===="

# kubelet NOFILE limit (systemd)
if systemctl is-active kubelet >/dev/null 2>&1; then
  echo -n "kubelet LimitNOFILE: "
  systemctl show kubelet -p LimitNOFILE --value
else
  echo "kubelet service: NOT RUNNING"
fi

# kubeadm version
if command -v kubeadm >/dev/null 2>&1; then
  echo -n "kubeadm version: "
  kubeadm version -o short
else
  echo "kubeadm: NOT INSTALLED"
fi

# kubectl client version
if command -v kubectl >/dev/null 2>&1; then
  echo -n "kubectl client version: "
  kubectl version --client --short
else
  echo "kubectl: NOT INSTALLED"
fi

# kubelet version
if command -v kubelet >/dev/null 2>&1; then
  echo -n "kubelet version: "
  kubelet --version
else
  echo "kubelet binary: NOT FOUND"
fi

echo "================================"


sleep 3
echo "Continuing after 3 seconds"




echo ">>> Installing crio......"

PROJECT_PATH=prerelease:/main

cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/rpm/repodata/repomd.xml.key
EOF

sleep 5
echo "Continuing after 5 seconds"

sudo dnf install -y container-selinux

sudo dnf install -y cri-o
sudo systemctl start crio.service
sudo systemctl enable crio.service




sleep 3
echo "Continuing after 3 seconds"


# CRI-O cgroup manager (SYSTEMD)
echo ">>> Ensuring CRI-O uses systemd cgroup manager"

CRIO_CONF="/etc/crio/crio.conf.d/10-crio.conf"

if grep -q '^cgroup_manager' "$CRIO_CONF"; then
  sudo sed -i 's/^cgroup_manager.*/cgroup_manager = "systemd"/' "$CRIO_CONF"
else
  sudo sed -i '/^\[crio.runtime\]/a cgroup_manager = "systemd"' "$CRIO_CONF"
fi


# kubelet cgroup driver (SYSTEMD)
echo ">>> Ensuring kubelet uses systemd cgroup driver"

KUBELET_CFG="/var/lib/kubelet/config.yaml"

if grep -q '^cgroupDriver:' "$KUBELET_CFG"; then
  sudo sed -i 's/^cgroupDriver:.*/cgroupDriver: systemd/' "$KUBELET_CFG"
else
  echo "cgroupDriver: systemd" | sudo tee -a "$KUBELET_CFG"
fi


# Restart services (correct order)
echo ">>> Restarting CRI-O and kubelet"

sudo systemctl daemon-reexec
sudo systemctl restart crio
sudo systemctl restart kubelet


# Validation
echo "===== Validation ====="

echo -n "CRI-O cgroup manager: "
crio config | grep cgroup_manager || true

echo -n "kubelet cgroup driver: "
grep cgroupDriver /var/lib/kubelet/config.yaml || true


echo ">>> Restarting kubelet and Crio"

sleep 5
echo "Continuing after 5 seconds"

sudo systemctl restart kubelet

sudo systemctl enable crio.service

sudo systemctl enable kubelet

echo ">>> kubelet and crio restarted............"

sleep 10
echo "Continuing after 10 seconds"


sudo systemctl stop kubelet

sudo systemctl restart crio
sudo systemctl restart kubelet

echo ">>>Again kubelet and crio restarted............"

echo ">>> kubeadm worker node setup completed add kubeadm join command from the command"

echo ">>>  kubeadm token create --print-join-command"