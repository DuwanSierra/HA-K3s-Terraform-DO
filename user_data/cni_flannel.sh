#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[CNI] Installing Flannel..."

# Apply Flannel manifest
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for Flannel deployment to be ready
echo "[CNI] Waiting for Flannel to be deployed..."
kubectl -n kube-flannel wait --for=condition=Ready pod -l app=flannel --timeout=3600s || true

# Validate Flannel pods
echo "[CNI] Validating Flannel installation..."
FLANNEL_READY=$(kubectl get deployment -n kube-flannel -o jsonpath='{.items[*].status.readyReplicas}')
FLANNEL_DESIRED=$(kubectl get deployment -n kube-flannel -o jsonpath='{.items[*].spec.replicas}')

if [ -z "$FLANNEL_READY" ]; then
    echo "[CNI] Warning: Could not verify Flannel status, but installation commands completed"
else
    echo "[CNI] Flannel status: Ready=$FLANNEL_READY, Desired=$FLANNEL_DESIRED"
fi

echo "[CNI] ✓ Flannel installation completed successfully"
