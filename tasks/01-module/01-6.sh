#!/usr/bin/env bash
set -euo pipefail

# Node Registration via CSR (Certificate-based Authentication)
# This script helps register a GCP worker node to local control plane using CSR

# Configuration
WORKER_NAME="worker1"
WORKER_ZONE="us-central1-a"
CONTROL_PLANE_IP="<YOUR_LOCAL_IP>"
K8S_VERSION="v1.30.0"

echo "=========================================="
echo "Node Registration via CSR"
echo "=========================================="
echo ""

# ============================================
# Step 1: Generate Private Key and CSR on Worker
# ============================================
echo "[1/9] Generating private key and CSR on worker node..."
echo ""
echo "Run on worker node:"
echo ""
cat <<'EOF'
# Create directory
sudo mkdir -p /var/lib/kubelet/pki
cd /var/lib/kubelet/pki

# Generate private key
sudo openssl genrsa -out kubelet.key 2048
sudo chmod 600 kubelet.key

# Create CSR configuration
NODE_NAME=$(hostname)
cat <<CSR_CONF_EOF | sudo tee kubelet-csr.conf
[req]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[dn]
CN = system:node:${NODE_NAME}
O = system:nodes

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
CSR_CONF_EOF

# Generate CSR
sudo openssl req -new \
  -key kubelet.key \
  -out kubelet.csr \
  -config kubelet-csr.conf

# Verify CSR
sudo openssl req -in kubelet.csr -noout -text

# Display CSR for transfer
echo ""
echo "Copy this CSR to control plane:"
sudo cat kubelet.csr
EOF

# ============================================
# Step 2: Transfer CSR to Control Plane
# ============================================
echo ""
echo "[2/9] Transferring CSR to control plane..."
echo ""
echo "On control plane, save CSR:"
echo ""
cat <<'EOF'
mkdir -p /tmp/worker-csr
cd /tmp/worker-csr

# Save CSR content
cat > kubelet.csr <<'CSR_EOF'
-----BEGIN CERTIFICATE REQUEST-----
<PASTE CSR CONTENT HERE>
-----END CERTIFICATE REQUEST-----
CSR_EOF
EOF

# ============================================
# Step 3: Sign CSR with CA
# ============================================
echo ""
echo "[3/9] Signing CSR with Kubernetes CA..."
echo ""
echo "On control plane:"
echo ""
cat <<'EOF'
cd /tmp/worker-csr

# Verify CA files exist
ls -la /tmp/ca.crt /tmp/ca.key

# Sign CSR
sudo openssl x509 -req \
  -in kubelet.csr \
  -CA /tmp/ca.crt \
  -CAkey /tmp/ca.key \
  -CAcreateserial \
  -out kubelet.crt \
  -days 365 \
  -extensions v3_req \
  -extfile <(printf "[v3_req]\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth") \
  -sha256

# Verify certificate
openssl x509 -in kubelet.crt -noout -text
openssl verify -CAfile /tmp/ca.crt kubelet.crt

echo ""
echo "Certificate signed successfully!"
echo ""
echo "Display certificate for transfer:"
cat kubelet.crt
EOF

# ============================================
# Step 4: Transfer Certificate to Worker
# ============================================
echo ""
echo "[4/9] Transferring signed certificate to worker..."
echo ""
echo "Option 1: Using scp"
echo ""
cat <<EOF
scp /tmp/worker-csr/kubelet.crt ${WORKER_NAME}:/tmp/
scp /tmp/ca.crt ${WORKER_NAME}:/tmp/
EOF
echo ""
echo "Option 2: Manual copy"
echo ""
echo "On worker node:"
echo ""
cat <<'EOF'
# Save certificate
sudo tee /var/lib/kubelet/pki/kubelet.crt <<'CERT_EOF'
-----BEGIN CERTIFICATE-----
<PASTE CERTIFICATE CONTENT HERE>
-----END CERTIFICATE-----
CERT_EOF

# Save CA certificate
sudo tee /var/lib/kubelet/pki/ca.crt <<'CA_EOF'
-----BEGIN CERTIFICATE-----
<PASTE CA CERTIFICATE HERE>
-----END CERTIFICATE-----
CA_EOF

# Set permissions
sudo chmod 644 /var/lib/kubelet/pki/kubelet.crt
sudo chmod 644 /var/lib/kubelet/pki/ca.crt
sudo chmod 600 /var/lib/kubelet/pki/kubelet.key

# Verify files
ls -la /var/lib/kubelet/pki/
EOF

# ============================================
# Step 5: Create kubeconfig with Certificate Auth
# ============================================
echo ""
echo "[5/9] Creating kubeconfig with certificate authentication..."
echo ""
echo "On worker node:"
echo ""
cat <<EOF
CONTROL_PLANE_IP="${CONTROL_PLANE_IP}"
NODE_NAME=\$(hostname)

cat <<KUBECONFIG_EOF | sudo tee /var/lib/kubelet/kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/kubelet/pki/ca.crt
    server: https://\${CONTROL_PLANE_IP}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: kubelet-context
current-context: kubelet-context
users:
- name: kubelet
  user:
    client-certificate: /var/lib/kubelet/pki/kubelet.crt
    client-key: /var/lib/kubelet/pki/kubelet.key
KUBECONFIG_EOF
EOF

# ============================================
# Step 6: Configure kubelet with Webhook Auth
# ============================================
echo ""
echo "[6/9] Configuring kubelet with webhook authentication..."
echo ""
cat <<'EOF'
cat <<KUBELET_CONFIG_EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
    cacheTTL: 2m0s
  x509:
    clientCAFile: "/var/lib/kubelet/pki/ca.crt"
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
failSwapOn: false
clusterDNS:
  - "10.0.0.10"
clusterDomain: "cluster.local"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
cgroupDriver: "cgroupfs"
serverTLSBootstrap: true
rotateCertificates: true
KUBELET_CONFIG_EOF
EOF

# ============================================
# Step 7: Start kubelet
# ============================================
echo ""
echo "[7/9] Starting kubelet with certificate authentication..."
echo ""
cat <<'EOF'
# Stop previous kubelet if running
sudo pkill kubelet || true

# Set environment
export PATH=$PATH:/opt/k8s/bin:/opt/cni/bin
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

# Start kubelet
sudo /opt/k8s/bin/kubelet \
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

# Check kubelet is running
sleep 5
ps aux | grep kubelet
EOF

# ============================================
# Step 8: Check and Approve CSR (if needed)
# ============================================
echo ""
echo "[8/9] Checking for pending CSRs..."
echo ""
echo "On control plane:"
echo ""
cat <<'EOF'
# Check for pending CSRs
kubectl get csr

# If you see pending CSR, approve it
kubectl get csr -o name | xargs kubectl certificate approve

# Verify CSR is approved
kubectl get csr
EOF

# ============================================
# Step 9: Verify Node Registration
# ============================================
echo ""
echo "[9/9] Verifying node registration..."
echo ""
echo "On control plane:"
echo ""
cat <<EOF
# Check nodes
kubectl get nodes -o wide

# Expected output:
# NAME       STATUS   ROLES    AGE   VERSION   INTERNAL-IP
# ${WORKER_NAME}    Ready    <none>   3m    ${K8S_VERSION}   10.128.0.7

# Check node details
kubectl describe node ${WORKER_NAME}

# Test pod scheduling
kubectl run test-csr --image=nginx --restart=Never
kubectl get pods -o wide

# Cleanup test pod
kubectl delete pod test-csr
EOF

# ============================================
# Verification
# ============================================
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "1. Certificate chain:"
echo "   openssl verify -CAfile /var/lib/kubelet/pki/ca.crt /var/lib/kubelet/pki/kubelet.crt"
echo ""
echo "2. Node status:"
echo "   kubectl get nodes"
echo ""
echo "3. Certificate expiry:"
echo "   openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates"
echo ""

# ============================================
# Troubleshooting
# ============================================
echo "=========================================="
echo "Troubleshooting"
echo "=========================================="
echo ""
echo "Issue: Certificate verification failed"
echo "Solution:"
echo "  openssl verify -CAfile /var/lib/kubelet/pki/ca.crt /var/lib/kubelet/pki/kubelet.crt"
echo ""
echo "Issue: CSR stays pending"
echo "Solution:"
echo "  kubectl get csr <csr-name> -o yaml"
echo "  kubectl certificate approve <csr-name>"
echo ""
echo "Issue: Node not registering"
echo "Solution:"
echo "  1. Check kubelet logs: tail -f /var/log/kubelet.log"
echo "  2. Test connectivity: curl -k https://${CONTROL_PLANE_IP}:6443/healthz"
echo "  3. Check certificate permissions: ls -la /var/lib/kubelet/pki/"
echo ""

# ============================================
# Certificate Rotation
# ============================================
echo "=========================================="
echo "Certificate Rotation"
echo "=========================================="
echo ""
echo "Automatic rotation is enabled with:"
echo "  serverTLSBootstrap: true"
echo "  rotateCertificates: true"
echo ""
echo "Monitor rotation:"
echo "  kubectl get csr -w"
echo ""
echo "Check certificate expiry:"
echo "  openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates"
echo ""

# ============================================
# Cleanup
# ============================================
echo "=========================================="
echo "Cleanup Commands"
echo "=========================================="
echo ""
echo "To remove worker node:"
echo ""
echo "# On control plane"
echo "kubectl drain ${WORKER_NAME} --ignore-daemonsets --delete-emptydir-data"
echo "kubectl delete node ${WORKER_NAME}"
echo "kubectl get csr | grep ${WORKER_NAME} | awk '{print \$1}' | xargs kubectl delete csr"
echo ""
echo "# On worker node"
echo "sudo pkill kubelet"
echo "sudo rm -rf /var/lib/kubelet/pki/*"
echo ""

echo "=========================================="
echo "Script completed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Follow the commands above step by step"
echo "2. Verify node is registered: kubectl get nodes"
echo "3. Test pod scheduling"
echo "4. Monitor certificate rotation"
