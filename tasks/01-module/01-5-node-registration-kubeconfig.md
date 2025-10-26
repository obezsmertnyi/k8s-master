# Module 01-5: Register Node to Control Plane via Kubeconfig

## Overview

Register a GCP worker node to your local control plane using kubeconfig authentication (token-based).

**Architecture:**
- **Control Plane:** Local machine (laptop)
- **Worker Node:** GCP VM instance
- **Authentication:** kubeconfig with token

**Quick Start:**
```bash
# On GCP worker node
export CONTROL_PLANE_IP="<YOUR_IP>"
export CONTROL_PLANE_TOKEN="<YOUR_TOKEN>"
bash 01-5-worker.sh
```

See [01-5-worker.sh](./01-5-worker.sh) for automated setup script.

---

## Prerequisites

- ✅ Control plane running locally (from tasks 01-1, 01-2, 01-3)
- ✅ GCP VM instance created (e.g., `worker1`)
- ✅ Network connectivity between local machine and GCP VM
- ✅ **Firewall configured to allow port 6443** (see Step 0 below)

---

## Step 0: Configure Firewall on Control Plane

### 0.1 Get Your Public IP

```bash
# Get your local machine's public IP
curl ifconfig.me
```

### 0.2 Open Port 6443 on Local Firewall

**For Ubuntu/Debian (ufw):**

```bash
# Check firewall status
sudo ufw status

# Allow port 6443 from anywhere (for testing)
sudo ufw allow 6443/tcp

# Or allow only from GCP IP range (more secure)
sudo ufw allow from 35.0.0.0/8 to any port 6443 proto tcp

# Verify rule
sudo ufw status numbered
```

**For Fedora/RHEL (firewalld):**

```bash
# Check firewall status
sudo firewall-cmd --state

# Allow port 6443
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

**For iptables:**

```bash
# Allow port 6443
sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### 0.3 Configure Router/NAT (if behind NAT)

If your local machine is behind a router:

1. **Port Forwarding:**
   - Login to your router admin panel
   - Forward external port 6443 to your local machine's IP:6443
   - Note your router's public IP (use `curl ifconfig.me` from local machine)

2. **Use Router's Public IP:**
   - In kubeconfig, use router's public IP instead of local machine IP
   - Example: `server: https://<ROUTER_PUBLIC_IP>:6443`

### 0.4 Test Connectivity

```bash
# On control plane - check kube-apiserver is listening
sudo netstat -tlnp | grep 6443

# Expected output:
# tcp6       0      0 :::6443                 :::*                    LISTEN      12345/kube-apiserver

# Test from GCP worker node
gcloud compute ssh worker1 --zone=us-central1-a
curl -k https://<YOUR_PUBLIC_IP>:6443/healthz

# Expected output: ok
```

### 0.5 Security Considerations

**⚠️ Important:**
- Opening port 6443 to the internet exposes your API server
- For production, use VPN or private network
- For testing, consider IP whitelisting

**Recommended for testing:**

```bash
# Get GCP worker node's external IP
gcloud compute instances describe worker1 \
  --zone=us-central1-a \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)'

# Allow only from worker node IP
sudo ufw allow from <WORKER_EXTERNAL_IP> to any port 6443 proto tcp
```

---

## Step 1: Prepare GCP Worker Node

### 1.1 Connect to GCP VM

```bash
# From your local machine
gcloud compute ssh worker1 --zone=us-central1-a
```

### 1.2 Create Required Directories

```bash
sudo mkdir -p /opt/k8s/bin
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /var/lib/kubelet/pki
sudo mkdir -p /etc/containerd
sudo mkdir -p /opt/cni/bin
sudo mkdir -p /etc/cni/net.d
```

---

## Step 2: Install Components on Worker Node

### 2.1 Download kubelet

```bash
cd /opt/k8s/bin
sudo curl -L "https://dl.k8s.io/v1.30.0/bin/linux/amd64/kubelet" -o kubelet
sudo chmod +x kubelet
```

### 2.2 Download and Install containerd

```bash
sudo wget https://github.com/containerd/containerd/releases/download/v2.0.5/containerd-static-2.0.5-linux-amd64.tar.gz -O /tmp/containerd.tar.gz
sudo tar -xzf /tmp/containerd.tar.gz -C /opt/k8s/bin --strip-components=1
sudo chmod +x /opt/k8s/bin/*
```

### 2.3 Download CNI Plugins

```bash
sudo wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz -O /tmp/cni-plugins.tgz
sudo tar -xzf /tmp/cni-plugins.tgz -C /opt/cni/bin
```

---

## Step 3: Configure containerd

### 3.1 Create containerd Configuration

```bash
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
```

### 3.2 Start containerd

```bash
sudo nohup /opt/k8s/bin/containerd -c /etc/containerd/config.toml >/var/log/containerd.log 2>&1 &
```

### 3.3 Verify containerd is Running

```bash
ps aux | grep containerd
sudo ls -la /run/containerd/containerd.sock
```

---

## Step 4: Transfer kubeconfig from Control Plane

### 4.1 On Control Plane (Local Machine)

Get your kubeconfig:

```bash
cat ~/.kube/config
```

You should see something like:

```yaml
apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://<CONTROL_PLANE_IP>:6443
  name: test-env
contexts:
- context:
    cluster: test-env
    namespace: default
    user: test-user
  name: test-context
current-context: test-context
kind: Config
preferences: {}
users:
- name: test-user
  user:
    token: "1234567890"
```

**Important:** Replace `<CONTROL_PLANE_IP>` with your local machine's external IP that is accessible from GCP.

### 4.2 On Worker Node (GCP VM)

Create kubeconfig file:

```bash
cat <<EOF | sudo tee /var/lib/kubelet/kubeconfig
apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://<YOUR_LOCAL_IP>:6443
  name: test-env
contexts:
- context:
    cluster: test-env
    namespace: default
    user: test-user
  name: test-context
current-context: test-context
kind: Config
preferences: {}
users:
- name: test-user
  user:
    token: "<YOUR_TOKEN>"
EOF
```

**Note:** Make sure your local machine's firewall allows connections on port 6443 from GCP.

---

## Step 5: Create kubelet Configuration

### 5.1 Create kubelet config.yaml

```bash
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
```

---

## Step 6: Transfer CA Certificate

### 6.1 On Control Plane (Local Machine)

Get CA certificate:

```bash
sudo cat /tmp/ca.crt
```

### 6.2 On Worker Node (GCP VM)

Create CA certificate file:

```bash
sudo tee /var/lib/kubelet/ca.crt <<'EOF'
-----BEGIN CERTIFICATE-----
<PASTE YOUR CA CERTIFICATE HERE>
-----END CERTIFICATE-----
EOF
```

---

## Step 7: Start kubelet on Worker Node

### 7.1 Set Environment Variables

```bash
export PATH=$PATH:/opt/k8s/bin:/opt/cni/bin
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
```

### 7.2 Start kubelet

```bash
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

### 7.3 Check kubelet Logs

```bash
# Check if kubelet is running
ps aux | grep kubelet

# View logs (if using systemd)
sudo journalctl -u kubelet -f

# Or check process output
tail -f /var/log/kubelet.log
```

---

## Step 8: Verify Node Registration

### 8.1 On Control Plane (Local Machine)

Check nodes:

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME           STATUS   ROLES    AGE   VERSION   INTERNAL-IP      EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION
worker1        Ready    <none>   2m    v1.30.0   10.128.0.7       <none>        Ubuntu 24.04 LTS     6.14.0-33-generic
```

### 8.2 Check Node Details

```bash
kubectl describe node worker1
```

### 8.3 Test Pod Scheduling

Deploy a test pod to the worker node:

```bash
kubectl run test-nginx --image=nginx --restart=Never
kubectl get pods -o wide
```

---

## Troubleshooting

### Issue: Node Not Appearing

**Check:**
1. Network connectivity between control plane and worker
2. Firewall rules (port 6443 must be open)
3. kubeconfig server URL is correct
4. Token is valid

```bash
# Test connectivity from worker to control plane
curl -k https://<CONTROL_PLANE_IP>:6443/healthz
```

### Issue: Node in NotReady State

**Check:**
1. containerd is running
2. CNI plugins are installed
3. kubelet logs for errors

```bash
sudo systemctl status containerd
ls -la /opt/cni/bin
sudo journalctl -u kubelet -n 50
```

### Issue: Pods Not Starting

**Check:**
1. Container runtime endpoint
2. CNI configuration
3. Pod logs

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

---

## Component Summary

| Component | Location | Purpose |
|-----------|----------|---------|
| `/opt/k8s/bin/kubelet` | Worker | Main kubelet binary |
| `/opt/k8s/bin/containerd` | Worker | Container runtime |
| `/opt/cni/bin/*` | Worker | CNI plugins |
| `/var/lib/kubelet/kubeconfig` | Worker | Authentication config with token |
| `/var/lib/kubelet/config.yaml` | Worker | kubelet configuration |
| `/var/lib/kubelet/ca.crt` | Worker | Control plane CA certificate |
| `/etc/containerd/config.toml` | Worker | containerd configuration |
| `/run/containerd/containerd.sock` | Worker | CRI socket |

---

## Cleanup

To remove the worker node:

```bash
# On control plane
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
kubectl delete node worker1

# On worker node
sudo pkill kubelet
sudo pkill containerd
sudo rm -rf /var/lib/kubelet
sudo rm -rf /run/containerd
```

---

## Next Steps

- ✅ Node registered via kubeconfig (token-based auth)
- 📝 Next: Task 01-6 - Register node via CSR (certificate-based auth)

---

## References

- [Kubernetes kubelet Documentation](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
- [containerd Configuration](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)
- [CNI Plugins](https://github.com/containernetworking/plugins)
