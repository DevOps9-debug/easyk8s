#!/bin/bash
set -e

echo "=== Installing MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "=== Waiting for MetalLB controller ==="
kubectl wait -n metallb-system --for=condition=Available deployment/controller --timeout=120s

echo "=== Creating MetalLB IP Address Pool ==="
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

echo "=== Checking MetalLB resources ==="
kubectl -n metallb-system get ipaddresspools
kubectl -n metallb-system get l2advertisements
kubectl -n metallb-system get pods -o wide

echo "=== MetalLB setup complete ==="
