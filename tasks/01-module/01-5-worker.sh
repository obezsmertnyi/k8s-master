#!/usr/bin/env bash
set -euo pipefail

# Node Registration via kubeconfig (Token-based Authentication)
# Run this script on GCP worker node

# Configuration - Update these values
CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-127.0.0.1}"
CONTROL_PLANE_TOKEN="${CONTROL_PLANE_TOKEN:-1234567890}"
K8S_VERSION="v1.30.0"
CONTAINERD_VERSION="2.0.5"
CNI_VERSION="v1.6.2"
RUNC_VERSION="v1.2.6"

# Get host info
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo "=========================================="
echo "Node Registration via kubeconfig"
echo "=========================================="
echo ""
echo "Worker Node: $HOSTNAME"
echo "Worker IP: $HOST_IP"
echo "Control Plane: $CONTROL_PLANE_IP:6443"
echo ""

# ============================================
# Step 1: Create Required Directories
# ============================================
echo "[1/7] Creating required directories..."
sudo mkdir -p /opt/cni/bin
sudo mkdir -p /etc/cni/net.d
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /var/lib/kubelet/pki
sudo mkdir -p /var/lib/kubelet/pods
sudo mkdir -p /var/lib/kubelet/plugins
sudo mkdir -p /etc/containerd
sudo mkdir -p /var/lib/containerd
sudo mkdir -p /run/containerd

# Set permissions
sudo chmod 750 /var/lib/kubelet/pods
sudo chmod 750 /var/lib/kubelet/plugins
sudo chmod 711 /var/lib/containerd

echo "✓ Directories created"

# ============================================
# Step 2: Download and Install Components
# ============================================
echo ""
echo "[2/7] Downloading and installing components..."

# Download kubelet
if [ ! -f "/usr/local/bin/kubelet" ]; then
    echo "Downloading kubelet ${K8S_VERSION}..."
    sudo curl -L "https://dl.k8s.io/${K8S_VERSION}/bin/linux/amd64/kubelet" -o /usr/local/bin/kubelet
    sudo chmod 755 /usr/local/bin/kubelet
    echo "✓ kubelet installed"
fi

# Download containerd
if [ ! -f "/opt/cni/bin/containerd" ]; then
    echo "Downloading containerd ${CONTAINERD_VERSION}..."
    wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-static-${CONTAINERD_VERSION}-linux-amd64.tar.gz -O /tmp/containerd.tar.gz
    sudo tar zxf /tmp/containerd.tar.gz -C /opt/cni/
    rm /tmp/containerd.tar.gz
    echo "✓ containerd installed"
fi

# Download runc
if [ ! -f "/opt/cni/bin/runc" ]; then
    echo "Downloading runc ${RUNC_VERSION}..."
    sudo curl -L "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.amd64" -o /opt/cni/bin/runc
    sudo chmod 755 /opt/cni/bin/runc
    echo "✓ runc installed"
fi

# Download CNI plugins
if [ ! -f "/opt/cni/bin/bridge" ]; then
    echo "Downloading CNI plugins ${CNI_VERSION}..."
    wget https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz -O /tmp/cni-plugins.tgz
    sudo tar zxf /tmp/cni-plugins.tgz -C /opt/cni/bin/
    rm /tmp/cni-plugins.tgz
    echo "✓ CNI plugins installed"
fi

# Set permissions
sudo chmod -R 755 /opt/cni

echo "✓ All components installed"

# ============================================
# Step 3: Configure CNI Network
# ============================================
echo ""
echo "[3/7] Configuring CNI network..."

cat <<EOF | sudo tee /etc/cni/net.d/10-mynet.conf
{
    "cniVersion": "0.3.1",
    "name": "mynet",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "subnet": "10.22.0.0/16",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ]
    }
}
EOF

echo "✓ CNI network configured"

# ============================================
# Step 4: Configure containerd
# ============================================
echo ""
echo "[4/7] Configuring containerd..."

cat <<EOF | sudo tee /etc/containerd/config.toml
version = 3

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins.'io.containerd.cri.v1.runtime']
  enable_selinux = false
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  device_ownership_from_security_context = false

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"
  disable_snapshot_annotations = true

[plugins.'io.containerd.cri.v1.runtime'.cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = false
EOF

echo "✓ containerd configured"

# Start containerd
echo "Starting containerd..."
sudo nohup /opt/cni/bin/containerd -c /etc/containerd/config.toml >/var/log/containerd.log 2>&1 &

sleep 3

# Verify containerd is running
if pgrep -f containerd >/dev/null; then
    echo "✓ containerd is running"
    sudo ls -la /run/containerd/containerd.sock
else
    echo "✗ containerd failed to start"
    echo "Check logs: tail -f /var/log/containerd.log"
    exit 1
fi

# ============================================
# Step 5: Create kubeconfig
# ============================================
echo ""
echo "[5/7] Creating kubeconfig..."

cat <<EOF | sudo tee /var/lib/kubelet/kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://${CONTROL_PLANE_IP}:6443
  name: test-env
contexts:
- context:
    cluster: test-env
    namespace: default
    user: test-user
  name: test-context
current-context: test-context
preferences: {}
users:
- name: test-user
  user:
    token: "${CONTROL_PLANE_TOKEN}"
EOF

echo "✓ kubeconfig created"

# ============================================
# Step 6: Configure kubelet
# ============================================
echo ""
echo "[6/7] Configuring kubelet..."

cat <<EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: true
  webhook:
    enabled: false
authorization:
  mode: AlwaysAllow
clusterDomain: "cluster.local"
clusterDNS:
  - "10.0.0.10"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
failSwapOn: false
containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
cgroupDriver: "cgroupfs"
EOF

echo "✓ kubelet configured"

# ============================================
# Step 7: Start kubelet
# ============================================
echo ""
echo "[7/7] Starting kubelet..."

sudo PATH=$PATH:/opt/cni/bin:/usr/sbin /usr/local/bin/kubelet \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --config=/var/lib/kubelet/config.yaml \
  --root-dir=/var/lib/kubelet \
  --cert-dir=/var/lib/kubelet/pki \
  --hostname-override=$HOSTNAME \
  --node-ip=$HOST_IP \
  --pod-infra-container-image=registry.k8s.io/pause:3.10 \
  --cgroup-driver=cgroupfs \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --v=2 &

KUBELET_PID=$!
sleep 5

# Verify kubelet is running
if ps -p $KUBELET_PID > /dev/null; then
    echo "✓ kubelet is running (PID: $KUBELET_PID)"
else
    echo "✗ kubelet failed to start"
    exit 1
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "Worker Node Setup Complete!"
echo "=========================================="
echo ""
echo "Node Information:"
echo "  Hostname: $HOSTNAME"
echo "  IP: $HOST_IP"
echo "  kubelet PID: $KUBELET_PID"
echo ""
echo "Verification:"
echo "  1. Check kubelet logs: tail -f /var/log/kubelet.log"
echo "  2. Check containerd: ps aux | grep containerd"
echo "  3. On control plane: kubectl get nodes"
echo ""
echo "Expected output on control plane:"
echo "  NAME       STATUS   ROLES    AGE   VERSION"
echo "  $HOSTNAME  Ready    <none>   1m    $K8S_VERSION"
echo ""
