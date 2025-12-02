#!/bin/bash
set -e

echo "=== Updating system ==="
apt update && apt upgrade -y

echo "=== Enabling IP forwarding ==="
cat <<EOF >/etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
sysctl --system

echo "=== Disabling swap ==="
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "=== Installing Docker + containerd ==="
apt-get install -y ca-certificates curl gpg apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
> /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Configuring containerd ==="
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

echo "=== Installing Kubernetes components ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
| gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo \
"deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
> /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet

echo "=== Initializing Kubernetes cluster ==="
kubeadm init --pod-network-cidr=192.168.0.0/16

echo "=== Configuring kubectl ==="
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

echo "=== Installing Calico CNI ==="
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "=== Installing MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "=== Waiting for MetalLB pods ==="
kubectl wait --namespace metallb-system --for=condition=Available deployment/controller --timeout=90s

echo "=== Applying MetalLB IP Pool ==="
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.24-192.168.0.50
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advert
  namespace: metallb-system
EOF

echo "=== Generating worker join command ==="
kubeadm token create --print-join-command

echo "=== Master setup complete ==="
