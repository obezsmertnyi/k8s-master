# Module 01-6: Register Node to Control Plane via CSR

## Overview

Register a GCP worker node to your local control plane using Certificate Signing Request (CSR) - the production-ready, automated way.

**Architecture:**
- **Control Plane:** Local machine (laptop)
- **Worker Node:** GCP VM instance (with kubelet and containerd from task 01-5)
- **Authentication:** Client certificate signed by Kubernetes CA
- **Authorization:** CSR approval workflow

**Note:** This task builds on task 01-5. Ensure you have completed 01-5 first or have kubelet and containerd installed.

See [01-6.sh](./01-6.sh) for step-by-step commands.

---

## Prerequisites

- ✅ Control plane running locally with valid CA certificates
- ✅ GCP VM instance with kubelet and containerd installed (from task 01-5)
- ✅ Network connectivity between local machine and GCP VM
- ✅ CA certificate and key available at `/tmp/ca.crt` and `/tmp/ca.key`
- ✅ **Firewall configured to allow port 6443** (see task 01-5, Step 0)

---

## Important: Firewall Configuration

**Before starting, ensure port 6443 is accessible from GCP worker node.**

See detailed firewall setup instructions in [Task 01-5, Step 0](./01-5-node-registration-kubeconfig.md#step-0-configure-firewall-on-control-plane).

Quick checklist:
- ✅ Port 6443 open on local firewall
- ✅ Router port forwarding configured (if behind NAT)
- ✅ Test connectivity: `curl -k https://<YOUR_IP>:6443/healthz` from worker node

---

## Difference: Task 01-5 vs 01-6

| Aspect | Task 01-5 (kubeconfig + token) | Task 01-6 (CSR + certificate) |
|--------|--------------------------------|-------------------------------|
| **Authentication** | Static token in kubeconfig | Client certificate signed by CA |
| **Automation** | Manual token management | Standard kubelet CSR workflow |
| **Security** | Basic (token can be leaked) | Production-level (certificate rotation) |
| **Use Case** | Testing, development | Production clusters |

---

## Step 1: Generate Private Key and CSR on Worker Node

### 1.1 Connect to Worker Node

```bash
# From your local machine
gcloud compute ssh worker1 --zone=us-central1-a
```

### 1.2 Create Private Key

```bash
sudo mkdir -p /var/lib/kubelet/pki
cd /var/lib/kubelet/pki

# Generate 2048-bit RSA private key
sudo openssl genrsa -out kubelet.key 2048
sudo chmod 600 kubelet.key
```

### 1.3 Create CSR Configuration

```bash
NODE_NAME=$(hostname)

cat <<EOF | sudo tee kubelet-csr.conf
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
EOF
```

**Important:**
- `CN = system:node:<hostname>` - required format for node identity
- `O = system:nodes` - required group for node authorization

### 1.4 Generate CSR

```bash
sudo openssl req -new \
  -key kubelet.key \
  -out kubelet.csr \
  -config kubelet-csr.conf
```

### 1.5 Verify CSR

```bash
sudo openssl req -in kubelet.csr -noout -text
```

Expected output should show:
- Subject: `CN=system:node:<hostname>, O=system:nodes`
- Key Usage: `Digital Signature, Key Encipherment`
- Extended Key Usage: `TLS Web Client Authentication`

---

## Step 2: Transfer CSR to Control Plane

### 2.1 Copy CSR from Worker to Control Plane

```bash
# On worker node - display CSR
sudo cat /var/lib/kubelet/pki/kubelet.csr
```

### 2.2 On Control Plane (Local Machine)

Save the CSR:

```bash
# Create temporary directory
mkdir -p /tmp/worker-csr
cd /tmp/worker-csr

# Paste CSR content
cat > kubelet.csr <<'EOF'
-----BEGIN CERTIFICATE REQUEST-----
<PASTE CSR CONTENT HERE>
-----END CERTIFICATE REQUEST-----
EOF
```

Or use `scp`:

```bash
# From control plane
scp worker1:/var/lib/kubelet/pki/kubelet.csr /tmp/worker-csr/
```

---

## Step 3: Sign CSR with Kubernetes CA

### 3.1 Verify CA Certificate and Key

```bash
# Check CA files exist
ls -la /tmp/ca.crt /tmp/ca.key

# Verify CA certificate
openssl x509 -in /tmp/ca.crt -noout -text
```

### 3.2 Sign the CSR

```bash
cd /tmp/worker-csr

# Sign CSR with CA
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
```

### 3.3 Verify Signed Certificate

```bash
# Check certificate details
openssl x509 -in kubelet.crt -noout -text

# Verify certificate chain
openssl verify -CAfile /tmp/ca.crt kubelet.crt
```

Expected output: `kubelet.crt: OK`

---

## Step 4: Transfer Signed Certificate to Worker Node

### 4.1 Copy Certificate and CA to Worker

```bash
# From control plane
scp /tmp/worker-csr/kubelet.crt worker1:/tmp/
scp /tmp/ca.crt worker1:/tmp/
```

### 4.2 On Worker Node - Install Certificates

```bash
# Move certificates to kubelet directory
sudo mv /tmp/kubelet.crt /var/lib/kubelet/pki/
sudo mv /tmp/ca.crt /var/lib/kubelet/pki/

# Set proper permissions
sudo chmod 644 /var/lib/kubelet/pki/kubelet.crt
sudo chmod 644 /var/lib/kubelet/pki/ca.crt
sudo chmod 600 /var/lib/kubelet/pki/kubelet.key

# Verify files
ls -la /var/lib/kubelet/pki/
```

---

## Step 5: Create kubeconfig with Certificate Authentication

### 5.1 Get Control Plane IP

```bash
# On control plane - get your public IP
curl ifconfig.me
```

### 5.2 On Worker Node - Create kubeconfig

```bash
CONTROL_PLANE_IP="<YOUR_CONTROL_PLANE_IP>"
NODE_NAME=$(hostname)

cat <<EOF | sudo tee /var/lib/kubelet/kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/kubelet/pki/ca.crt
    server: https://${CONTROL_PLANE_IP}:6443
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
EOF
```

---

## Step 6: Configure kubelet

### 6.1 Create or Update kubelet Configuration

```bash
cat <<EOF | sudo tee /var/lib/kubelet/config.yaml
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
EOF
```

**Key differences from task 01-5:**
- `authentication.webhook.enabled: true` - enables webhook authentication
- `authorization.mode: Webhook` - uses webhook authorization
- `serverTLSBootstrap: true` - enables TLS bootstrapping
- `rotateCertificates: true` - enables automatic certificate rotation

---

## Step 7: Start kubelet on Worker Node

### 7.1 Stop Previous kubelet (if running)

```bash
sudo pkill kubelet
```

### 7.2 Start kubelet with Certificate Authentication

```bash
export PATH=$PATH:/opt/k8s/bin:/opt/cni/bin
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

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
```

### 7.3 Monitor kubelet Logs

```bash
# Check kubelet is running
ps aux | grep kubelet

# Monitor logs
tail -f /var/log/kubelet.log
```

---

## Step 8: Approve CSR on Control Plane (if using Kubernetes CSR API)

**Note:** If you manually signed the certificate in Step 3, you can skip this step. This step is for when kubelet automatically generates CSR requests.

### 8.1 Check for Pending CSRs

```bash
# On control plane
kubectl get csr
```

Expected output:

```
NAME                AGE   SIGNERNAME                            REQUESTOR           CONDITION
node-csr-xxxxx      10s   kubernetes.io/kube-apiserver-client-kubelet   system:node:worker1   Pending
```

### 8.2 Approve CSR

```bash
# Approve specific CSR
kubectl certificate approve node-csr-xxxxx

# Or approve all pending CSRs
kubectl get csr -o name | xargs kubectl certificate approve
```

### 8.3 Verify CSR is Approved

```bash
kubectl get csr
```

Expected output:

```
NAME                AGE   SIGNERNAME                            REQUESTOR           CONDITION
node-csr-xxxxx      1m    kubernetes.io/kube-apiserver-client-kubelet   system:node:worker1   Approved,Issued
```

---

## Step 9: Verify Node Registration

### 9.1 Check Nodes

```bash
# On control plane
kubectl get nodes -o wide
```

Expected output:

```
NAME       STATUS   ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION
worker1    Ready    <none>   3m    v1.30.0   10.128.0.7       <none>        Ubuntu 24.04 LTS     6.14.0-33-generic
```

### 9.2 Check Node Details

```bash
kubectl describe node worker1
```

Look for:
- `Conditions: Ready`
- `Addresses: InternalIP, Hostname`
- `System Info: kubelet version, container runtime`

### 9.3 Test Pod Scheduling

```bash
# Deploy test pod
kubectl run test-csr --image=nginx --restart=Never

# Check pod is running on worker
kubectl get pods -o wide

# Cleanup
kubectl delete pod test-csr
```

---

## Troubleshooting

### Issue: Certificate Verification Failed

**Symptoms:**
```
unable to load certificate: x509: certificate signed by unknown authority
```

**Solution:**
1. Verify CA certificate matches on control plane and worker
2. Check certificate chain:
   ```bash
   openssl verify -CAfile /var/lib/kubelet/pki/ca.crt /var/lib/kubelet/pki/kubelet.crt
   ```

### Issue: CSR Stays in Pending State

**Symptoms:**
```
kubectl get csr shows CONDITION: Pending
```

**Solution:**
1. Check kube-controller-manager is running
2. Verify CSR has correct CN and O fields:
   ```bash
   kubectl get csr <csr-name> -o yaml
   ```
3. Manually approve CSR:
   ```bash
   kubectl certificate approve <csr-name>
   ```

### Issue: Node Not Registering

**Symptoms:**
- `kubectl get nodes` doesn't show worker node

**Solution:**
1. Check kubelet logs for authentication errors
2. Verify network connectivity:
   ```bash
   curl -k https://<CONTROL_PLANE_IP>:6443/healthz
   ```
3. Check certificate permissions:
   ```bash
   ls -la /var/lib/kubelet/pki/
   ```

### Issue: Certificate Expired

**Symptoms:**
```
x509: certificate has expired or is not yet valid
```

**Solution:**
1. Check certificate validity:
   ```bash
   openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -dates
   ```
2. Re-generate and sign new certificate (repeat Steps 1-4)

---

## Certificate Rotation

### Automatic Rotation (Recommended)

With `rotateCertificates: true` in kubelet config, certificates will automatically rotate before expiry.

Monitor rotation:

```bash
# Check certificate expiry
kubectl get csr

# Watch for new CSR requests
kubectl get csr -w
```

### Manual Rotation

If automatic rotation fails:

1. Generate new CSR (Step 1)
2. Sign with CA (Step 3)
3. Update certificates (Step 4)
4. Restart kubelet (Step 7)

---

## Security Best Practices

### 1. Protect Private Keys

```bash
# Ensure proper permissions
sudo chmod 600 /var/lib/kubelet/pki/kubelet.key
sudo chown root:root /var/lib/kubelet/pki/kubelet.key
```

### 2. Regular Certificate Rotation

- Set certificate validity to 90 days or less
- Enable automatic rotation with `rotateCertificates: true`
- Monitor certificate expiry dates

### 3. Secure CA Private Key

```bash
# On control plane
sudo chmod 600 /tmp/ca.key
sudo chown root:root /tmp/ca.key
```

### 4. Use RBAC

Ensure proper RBAC policies for node authorization:

```bash
kubectl get clusterrolebinding system:node
```

---

## Component Summary

| Component | Location | Purpose |
|-----------|----------|---------|
| `/var/lib/kubelet/pki/kubelet.key` | Worker | Node private key (keep secret!) |
| `/var/lib/kubelet/pki/kubelet.csr` | Worker | Certificate signing request |
| `/var/lib/kubelet/pki/kubelet.crt` | Worker | Signed client certificate |
| `/var/lib/kubelet/pki/ca.crt` | Worker | Kubernetes CA certificate |
| `/var/lib/kubelet/kubeconfig` | Worker | kubeconfig with certificate auth |
| `/tmp/ca.crt` | Control Plane | Kubernetes CA certificate |
| `/tmp/ca.key` | Control Plane | Kubernetes CA private key |

---

## Comparison: Token vs Certificate Authentication

| Feature | Token (Task 01-5) | Certificate (Task 01-6) |
|---------|-------------------|-------------------------|
| **Setup Complexity** | Simple | Moderate |
| **Security** | Basic | High |
| **Rotation** | Manual | Automatic |
| **Revocation** | Delete token | Revoke certificate |
| **Audit Trail** | Limited | Full (via CSR) |
| **Production Ready** | ❌ No | ✅ Yes |

---

## Cleanup

To remove the worker node:

```bash
# On control plane
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node worker1

# Delete CSRs
kubectl get csr | grep worker1 | awk '{print $1}' | xargs kubectl delete csr

# On worker node
sudo pkill kubelet
sudo rm -rf /var/lib/kubelet/pki/*
```

---

## Next Steps

- ✅ Node registered via CSR (certificate-based auth)
- ✅ Production-ready authentication setup
- 📝 Next: Module 02 - Custom Kubernetes Controller

---

## References

- [Kubernetes TLS Bootstrapping](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/)
- [Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [kubelet Authentication/Authorization](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/)
- [OpenSSL CSR Guide](https://www.openssl.org/docs/man1.1.1/man1/req.html)
