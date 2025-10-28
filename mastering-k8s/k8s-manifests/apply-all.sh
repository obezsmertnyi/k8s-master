#!/bin/bash

# Script to apply all Kubernetes manifests for full cluster setup
# This includes CoreDNS, kubernetes Service, and controller RBAC
# Note: kube-proxy is started automatically by setup.sh

set -e

# Set kubectl path
KUBECTL=${KUBECTL:-"../kubebuilder/bin/kubectl"}

echo "=== Applying Kubernetes Manifests ==="
echo ""
echo "Using kubectl: $KUBECTL"
echo ""

# Get HOST_IP
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Detected HOST_IP: $HOST_IP"
echo ""

# Update kubernetes Endpoints with actual HOST_IP
echo "Step 1: Updating kubernetes Endpoints..."

# Check if kubernetes Service exists
if $KUBECTL get svc kubernetes -n default &>/dev/null; then
    echo "kubernetes Service already exists, updating Endpoints only..."
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: Endpoints
metadata:
  name: kubernetes
  namespace: default
  labels:
    endpointslice.kubernetes.io/skip-mirror: "true"
subsets:
- addresses:
  - ip: $HOST_IP
  ports:
  - name: https
    port: 6443
    protocol: TCP
EOF
else
    echo "Creating kubernetes Service and Endpoints..."
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kubernetes
  namespace: default
spec:
  clusterIP: 10.0.0.1
  ports:
  - port: 443
    targetPort: 6443
    protocol: TCP
    name: https
  type: ClusterIP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: kubernetes
  namespace: default
  labels:
    endpointslice.kubernetes.io/skip-mirror: "true"
subsets:
- addresses:
  - ip: $HOST_IP
  ports:
  - name: https
    port: 6443
    protocol: TCP
EOF
fi

echo "[OK] kubernetes Endpoints updated"
echo ""

# Apply namespace
echo "Step 2: Creating kube-system namespace..."
$KUBECTL apply -f 01-namespace.yaml
echo "[OK] kube-system namespace created"
echo ""

# Apply CoreDNS with updated HOST_IP
echo "Step 3: Deploying CoreDNS..."
cat 03-coredns.yaml | sed "s/192.168.88.142/$HOST_IP/g" | $KUBECTL apply -f -
echo "[OK] CoreDNS deployed"
echo ""

# Apply controller RBAC
echo "Step 4: Creating RBAC for newresource-controller..."
$KUBECTL apply -f 05-controller-rbac.yaml
echo "[OK] Controller RBAC created"
echo ""

echo "=== Verification ==="
echo ""

echo "Checking CoreDNS status:"
$KUBECTL get pods -n kube-system -l k8s-app=kube-dns
echo ""

echo "Checking kubernetes Service:"
$KUBECTL get svc kubernetes -n default
$KUBECTL get endpoints kubernetes -n default
echo ""

echo "Checking controller ServiceAccount:"
$KUBECTL get sa newresource-controller -n default
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Note: kube-proxy is running as a host process (started by setup.sh)"
echo "You can verify with: pgrep -f kube-proxy"
echo ""
echo "You can now run the controller with leader election:"
echo "  cd ../new-controller"
echo "  go run main.go --leader-elect=true --leader-election-namespace=default"
echo ""
