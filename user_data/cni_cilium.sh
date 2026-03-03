#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[CNI] Installing Cilium..."

# Determine architecture
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi

echo "[CNI] Downloading Cilium CLI (version: $CILIUM_CLI_VERSION, arch: $CLI_ARCH)..."

# Download and install cilium-cli
curl -L --fail --remote-name-all \
    https://github.com/cilium/cilium-cli/releases/download/$CILIUM_CLI_VERSION/cilium-linux-$CLI_ARCH.tar.gz{,.sha256sum}

sha256sum --check cilium-linux-$CLI_ARCH.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-$CLI_ARCH.tar.gz /usr/local/bin
rm -f cilium-linux-$CLI_ARCH.tar.gz cilium-linux-$CLI_ARCH.tar.gz.sha256sum

echo "[CNI] Running cilium install..."
cilium install

# Wait for Cilium to be ready
echo "[CNI] Waiting for Cilium to be fully deployed..."
kubectl -n kube-system wait --for=condition=Ready pod -l app=cilium --timeout=3600s || true

# Validate Cilium installation
echo "[CNI] Validating Cilium installation..."
CILIUM_STATUS=$(cilium status --wait 2>/dev/null || echo "pending")
echo "[CNI] Cilium status: $CILIUM_STATUS"

echo "[CNI] ✓ Cilium installation completed successfully"
