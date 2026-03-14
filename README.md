# 🚀 Devops-K8s — Hybrid Multi-Region HA Kubernetes Cluster

> **End-to-end automation for a production cross-network HA Kubernetes cluster spanning multiple regions and cloud/on-prem nodes — featuring HAProxy load balancing, etcd quorum management, persistent storage, and RBAC — built for hybrid enterprise infrastructure with security and compliance in mind.**

---

## 📌 What This Project Solves

Managing a **highly available Kubernetes cluster across multiple networks, regions, and cloud providers** is one of the hardest real-world infrastructure challenges. This repo automates the entire lifecycle — from bootstrapping nodes to recovering a broken etcd quorum — with production-grade tooling on **Rocky Linux 9**.

---

## 🏗️ Architecture Overview

```
                        ┌─────────────────────────────────────────────┐
                        │           HAProxy Load Balancer              │
                        │         isiem-proxy-host (10.10.1.36)        │
                        │              Public IP + VPN                 │
                        └──────────────┬──────────────────────────────┘
                                       │ :6443
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
   ┌──────────▼──────────┐  ┌──────────▼──────────┐  ┌─────────▼───────────┐
   │  Control Plane 1    │  │  Control Plane 2    │  │  Control Plane 3   │
   │  isu-k8s-cp         │  │  stpi-k8s-master    │  │  gcp-k8s-master    │
   │  172.18.0.101       │  │  172.26.0.8         │  │  10.10.1.26        │
   │  (On-Prem / ISU)    │  │  (On-Prem / STPI)   │  │  (Google Cloud)    │
   └──────────┬──────────┘  └──────────┬──────────┘  └─────────┬──────────┘
              │                        │                        │
              └────────────────────────┼────────────────────────┘
                                       │  etcd quorum (cross-VPN)
                        ┌──────────────▼──────────────┐
                        │        Worker Nodes          │
                        │   (Multiple regions/zones)   │
                        └──────────────────────────────┘
```

> ⚡ All control planes are on **different networks**, connected via **VPN** — making this a true cross-network, hybrid HA setup.

---

## ✨ Key Features

| Feature | Detail |
|---|---|
| 🌐 **Multi-Region Control Plane** | 3 control planes across on-prem (ISU, STPI) and GCP — connected over VPN |
| ⚖️ **HAProxy Load Balancing** | TCP-mode round-robin with health checks on all API servers |
| 🧠 **etcd Quorum Management** | Handles cross-network etcd peer certs (SANs), stale member removal, clean rejoin |
| 🔒 **RBAC Automation** | Scripts for Linux user creation, Kubernetes user binding, and kubeconfig distribution |
| 📦 **Persistent Storage** | Supports both NFS (`nfs-subdir-external-provisioner`) and local-path provisioner |
| 🌿 **Cilium CNI** | eBPF-powered networking with kube-proxy replacement, Hubble observability, Gateway API |
| 🔁 **Full Recovery Playbooks** | Documented + scripted recovery for etcd split-brain and hostname-change failures |
| 🤖 **End-to-End Automation** | Single `isiem-k8s-setup.sh` script with interactive menu + `--auto` mode for CI/Ansible |

---

## 📁 Repository Structure

```
Devops-K8s/
├── isiem-k8s-setup.sh              # 🔧 Main automation script (all roles)
├── config.env                      # ⚙️  Configuration file (IPs, tokens, versions)
├── slave-nodes.sh                  # 👷 Worker node join helper
├── hybrid-multi-region-ha-cluster-setup.txt  # 📖 Full setup reference guide
├── RBAC-Kubernetes/
│   ├── create-linux-user.sh        # 👤 Create OS-level user on node
│   ├── create-k8s-user.sh          # 🔑 Create K8s user with cert-based auth
│   ├── move-kubeconfig.sh          # 📤 Distribute kubeconfig to user
│   └── steps-to-execute.txt        # 📋 RBAC execution order guide
└── README.md
```

---

## ⚡ Quick Start

### Prerequisites
- Rocky Linux 9.x on all nodes
- VPN connectivity between all nodes (cross-network)
- Root/sudo access
- HAProxy node reachable from all control-planes and workers

### 1. Clone & Configure

```bash
git clone https://github.com/sandeepdash-mlops/Devops-K8s.git
cd Devops-K8s
cp config.env my-config.env
vim my-config.env   # Fill in your IPs, hostnames, tokens
```

### 2. Run Setup (Interactive)

```bash
sudo bash isiem-k8s-setup.sh --config my-config.env
```

```
══════════════════════════════════════
  ISIEM HA Kubernetes Setup
══════════════════════════════════════
  Select an action:
   1) Setup HAProxy Load Balancer
   2) Prepare node (common prerequisites)
   3) Initialize FIRST control-plane
   4) Join additional control-plane
   5) Join worker node
   6) Install Cilium CNI
   7) Setup Storage (local-path or NFS)
   8) Recovery: Remove stale etcd member & rejoin control-plane
   9) Recovery: Reset & rejoin worker node
   0) Exit
```

### 3. Non-Interactive (CI / Ansible)

```bash
# Set NODE_ROLE in config.env, then:
sudo bash isiem-k8s-setup.sh --config my-config.env --auto
```

---

## 🔒 RBAC — Kubernetes User Management

The `RBAC-Kubernetes/` module handles the full lifecycle of granting a developer or operator scoped access to the cluster.

```bash
# Step 1 — Create Linux user on the node
bash RBAC-Kubernetes/create-linux-user.sh <username>

# Step 2 — Create K8s user with certificate-based auth + role binding
bash RBAC-Kubernetes/create-k8s-user.sh <username> <namespace> <role>

# Step 3 — Deliver kubeconfig to the user
bash RBAC-Kubernetes/move-kubeconfig.sh <username>
```

See `RBAC-Kubernetes/steps-to-execute.txt` for the full execution order and examples.

---

## 🔁 Failure Recovery Playbooks

### Case 1 — Stale etcd Member (Control-Plane Rejoin)
When a control-plane is rebuilt or re-provisioned, the old etcd membership blocks the rejoin.

```bash
# On a healthy control-plane — remove the stale etcd member
kubectl -n kube-system exec -it etcd-<healthy-cp> -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  member remove <STALE_MEMBER_ID>

# Then on the broken node — clean state and rejoin
sudo bash isiem-k8s-setup.sh   # Choose option 8
```

### Case 2 — Hostname Changed on Worker Node
```bash
# Update /etc/hosts with new hostname, then:
sudo bash isiem-k8s-setup.sh   # Choose option 9
```

---

## 🧰 Tech Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![Rocky Linux](https://img.shields.io/badge/Rocky_Linux-9.x-10B981?style=flat-square&logo=rockylinux&logoColor=white)
![HAProxy](https://img.shields.io/badge/HAProxy-LB-FF6600?style=flat-square)
![Cilium](https://img.shields.io/badge/Cilium-CNI-F8C517?style=flat-square&logo=cilium&logoColor=black)
![CRI-O](https://img.shields.io/badge/CRI--O-Runtime-CC0000?style=flat-square)
![etcd](https://img.shields.io/badge/etcd-Quorum-419EDA?style=flat-square)
![Helm](https://img.shields.io/badge/Helm-3-0F1689?style=flat-square&logo=helm&logoColor=white)
![NFS](https://img.shields.io/badge/NFS-Storage-6B7280?style=flat-square)

---

## 📐 Design Decisions

**Why HAProxy over a cloud LB?**
This cluster spans on-prem and cloud nodes — a cloud-native LB can't front all three. HAProxy runs on a dedicated proxy node with VPN access to all control-planes, making it the only viable cross-network solution.

**Why Cilium over flannel/calico?**
Cilium replaces kube-proxy entirely using eBPF, giving better performance and built-in observability via Hubble — essential for cross-region traffic visibility.

**Why CRI-O over containerd/Docker?**
CRI-O is purpose-built for Kubernetes, lighter weight, and better aligned with OCI standards — reducing attack surface for compliance-sensitive environments.

---

## 💬 Connect

If you found this project helpful or have any questions, feel free to reach out!

📧 **Email:** sandeepdashmlops@gmail.com

💻 **GitHub:** [github.com/sandeepdash-mlops](https://github.com/sandeepdash-mlops)

---

<p align="center">
  Built with 🔧 by <a href="https://github.com/sandeepdash-mlops">sandeepdash-mlops</a> — real infrastructure, real problems, real fixes.
</p>
