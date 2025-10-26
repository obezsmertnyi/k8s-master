#!/usr/bin/env zsh
set -euo pipefail

# GCP Cloud Controller Manager Setup Script
# This script sets up a mock GCP environment with Cloud Controller Manager
# 
# Tasks:
# 1. Deploy CCM (Cloud Controller Manager) for GCP
# 2. Configure cloud-provider external in control plane
# 3. Setup 169.254.169.254/32 on localhost
# 4. Create service account and configure cloud.conf and sa.json
# 5. Deploy mock metadata server
# 6. Start cloud-controller-manager
# 7. Register node in cloud
# 8. Deploy test deployment
# 9. Create LoadBalancer and get real IP address

# Configuration
PROJECT_ID="devops-automation"
NUMERIC_PROJECT_ID="46529416112"
INSTANCE_NAME="k8s-test-instance"
INSTANCE_ID="2983839776455586411"
SA_EMAIL="terraform@devops-automation.iam.gserviceaccount.com"
NETWORK_NAME="default"
LOCAL_ZONE="us-central1-a"
NODE_TAGS="kubernetes-node"
HOST_IP=$(hostname -I | awk '{print $1}')

echo "=========================================="
echo "GCP Cloud Controller Manager Setup"
echo "=========================================="
echo ""

# ============================================
# Step 1: Create Service Account with proper roles
# ============================================
echo "[1/11]Creating GCP Service Account configuration..."
echo ""
echo "# In GCP Console, create a service account with these roles:"
echo "# - Compute Engine Service Agent"
echo "# - Kubernetes Engine Service Agent"
echo "# - Service Account User"
echo ""
echo "# Or via gcloud CLI:"
echo "# gcloud iam service-accounts create terraform \\"
echo "#   --display-name='Terraform Service Account' \\"
echo "#   --project=${PROJECT_ID}"
echo ""
echo "# Grant necessary roles with conditions (access only to kubernetes-node tagged resources):"
echo "# "
echo "# 1. Compute Instance Admin - only for instances with kubernetes-node tag:"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/compute.instanceAdmin.v1' \\"
echo "#   --condition='expression=resource.matchTag(\"${PROJECT_ID}/node-tags\", \"${NODE_TAGS}\"),title=kubernetes-node-access,description=Access only to kubernetes-node tagged resources'"
echo ""
echo "# 2. Network Admin - limited access:"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/compute.networkAdmin' \\"
echo "#   --condition='expression=resource.name.startsWith(\"projects/${PROJECT_ID}/global/networks/${NETWORK_NAME}\"),title=default-network-only,description=Access only to default network'"
echo ""
echo "# 3. Compute Load Balancer Admin (for LoadBalancer services):"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/compute.loadBalancerAdmin' \\"
echo "#   --condition=None"
echo ""
echo "# 4. Kubernetes Engine Service Agent:"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/container.serviceAgent' \\"
echo "#   --condition=None"
echo ""
echo "# 5. Kubernetes Engine Cluster Admin (if needed for cluster management):"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/container.clusterAdmin' \\"
echo "#   --condition=None"
echo ""
echo "# 6. Service Account User:"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/iam.serviceAccountUser' \\"
echo "#   --condition=None"
echo ""
echo "# 7. Secret Manager Secret Accessor (if using secrets):"
echo "# gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
echo "#   --member='serviceAccount:${SA_EMAIL}' \\"
echo "#   --role='roles/secretmanager.secretAccessor' \\"
echo "#   --condition=None"
echo ""
echo "# Download service account key (saved outside repo to avoid committing):"
echo "# gcloud iam service-accounts keys create ../../../gce_metadata_server/sa.json \\"
echo "#   --iam-account=${SA_EMAIL}"
echo ""
echo "# ============================================"
echo "# Optional: Create a real GCP instance for testing"
echo "# ============================================"
echo "# "
echo "# Create minimal e2-micro instance with kubernetes-node tag:"
echo "# gcloud compute instances create ${INSTANCE_NAME} \\"
echo "#   --project=${PROJECT_ID} \\"
echo "#   --zone=${LOCAL_ZONE} \\"
echo "#   --machine-type=e2-micro \\"
echo "#   --network-interface=network-tier=PREMIUM,subnet=default \\"
echo "#   --tags=${NODE_TAGS} \\"
echo "#   --metadata=enable-oslogin=true \\"
echo "#   --maintenance-policy=MIGRATE \\"
echo "#   --service-account=${SA_EMAIL} \\"
echo "#   --scopes=https://www.googleapis.com/auth/cloud-platform \\"
echo "#   --image-family=ubuntu-2204-lts \\"
echo "#   --image-project=ubuntu-os-cloud \\"
echo "#   --boot-disk-size=10GB \\"
echo "#   --boot-disk-type=pd-standard"
echo ""
echo "# Get instance ID after creation:"
echo "# INSTANCE_ID=\$(gcloud compute instances describe ${INSTANCE_NAME} \\"
echo "#   --zone=${LOCAL_ZONE} \\"
echo "#   --format='value(id)')"
echo ""
echo "# Update config.json with real instance ID:"
echo "# sed -i 's/\"ID\": [0-9]*/\"ID\": '\$INSTANCE_ID'/' config.json"
echo ""
echo "# Delete instance after testing:"
echo "# gcloud compute instances delete ${INSTANCE_NAME} \\"
echo "#   --zone=${LOCAL_ZONE} \\"
echo "#   --quiet"
echo ""

# ============================================
# Step 2: Create config.json for mock metadata server
# ============================================
echo "[2/11] Creating config.json..."
cat > config.json <<EOF
{
  "ComputeMetadata": {
    "V1": {
      "Project": {
        "ProjectID": "${PROJECT_ID}",
        "NumericProjectID": ${NUMERIC_PROJECT_ID}
      },
      "Instance": {
        "name": "${INSTANCE_NAME}",
        "id": ${INSTANCE_ID},
        "ServiceAccounts": {
          "default": {
            "Email": "${SA_EMAIL}",
            "Scopes": [
              "https://www.googleapis.com/auth/cloud-platform",
              "https://www.googleapis.com/auth/userinfo.email"
            ]
          }
        }
      }
    }
  }
}
EOF
echo "✅ config.json created"

# ============================================
# Step 3: Create cloud.conf for CCM
# ============================================
echo "[3/11] Creating cloud.conf..."
cat > cloud.conf <<EOF
[global]
project-id     = "${PROJECT_ID}"
network-name   = "${NETWORK_NAME}"
local-zone     = "${LOCAL_ZONE}"
node-tags      = "${NODE_TAGS}"
EOF
echo "✅ cloud.conf created"

# ============================================
# Step 4: Check for sa.json (service account key)
# ============================================
echo "[4/11] Checking for sa.json..."
mkdir -p gce_metadata_server

# Check if sa.json exists in the expected location
if [ -f "../../../gce_metadata_server/sa.json" ]; then
  echo "Found sa.json in ../../../gce_metadata_server/"
  cp ../../../gce_metadata_server/sa.json gce_metadata_server/sa.json
  echo "Copied sa.json to gce_metadata_server/"
elif [ -f "gce_metadata_server/sa.json" ]; then
  echo "sa.json already exists in gce_metadata_server/"
else
  echo "sa.json not found!"
  echo ""
  echo "Please create service account key first:"
  echo "  gcloud iam service-accounts keys create ../../../gce_metadata_server/sa.json \\"
  echo "    --iam-account=${SA_EMAIL}"
  echo ""
  echo "Then run this script again."
  exit 1
fi

# ============================================
# Step 5: Setup metadata server IP
# ============================================
echo "[5/11] Setting up metadata server IP (169.254.169.254)..."
sudo ip addr add 169.254.169.254/32 dev lo 2>/dev/null || echo "IP already configured"
echo "✅ Metadata IP configured"

# ============================================
# Step 6: Start mock GCP metadata server
# ============================================
echo "[6/11] Starting mock GCP metadata server..."

# Check if gce_metadata_server exists, if not - download it
if [ ! -f "kubebuilder/bin/gce_metadata_server" ]; then
  echo "gce_metadata_server not found, downloading..."
  mkdir -p kubebuilder/bin
  
  # Download from salrashid123/gce_metadata_server releases (v4.1.1)
  sudo wget https://github.com/salrashid123/gce_metadata_server/releases/download/v4.1.1/gce_metadata_server_4.1.1_linux_amd64 \
    -O kubebuilder/bin/gce_metadata_server
  
  sudo chmod +x kubebuilder/bin/gce_metadata_server
  echo "✅ gce_metadata_server v4.1.1 downloaded"
fi

# Check if cloud-controller-manager exists, if not - extract from Docker image
if [ ! -f "kubebuilder/bin/cloud-controller-manager" ]; then
  echo "cloud-controller-manager not found, extracting from Docker image..."
  mkdir -p kubebuilder/bin
  
  # GCP CCM doesn't have pre-built binaries in releases
  # Extract from Docker image instead (for k8s 1.30.0, use v33.4.0)
  echo "Pulling GCP CCM v33.4.0 Docker image..."
  
  # Pull Docker image
  docker pull gcr.io/k8s-staging-cloud-provider-gcp/cloud-controller-manager:v33.4.0
  
  # Create temporary container and extract binary
  docker create --name temp-ccm gcr.io/k8s-staging-cloud-provider-gcp/cloud-controller-manager:v33.4.0
  docker cp temp-ccm:/cloud-controller-manager kubebuilder/bin/cloud-controller-manager
  docker rm temp-ccm
  
  # Set permissions
  chmod +x kubebuilder/bin/cloud-controller-manager
  
  echo "✅ GCP cloud-controller-manager v33.4.0 extracted from Docker image"
fi

# Start metadata server
if [ -f "kubebuilder/bin/gce_metadata_server" ]; then
  # Kill existing metadata server if running
  sudo pkill -f gce_metadata_server || true
  sleep 2

  sudo kubebuilder/bin/gce_metadata_server \
    --logtostderr \
    --configFile=config.json \
    --port=:80 \
    --interface=169.254.169.254 \
    --serviceAccountFile=gce_metadata_server/sa.json &
  
  METADATA_PID=$!
  echo "✅ Metadata server started (PID: $METADATA_PID)"
  sleep 3
  
  # Test metadata server
  echo "Testing metadata server..."
  curl -v -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/\?recursive\=true 2>&1 | head -20 || echo "Metadata server test failed"
fi

# ============================================
# Step 7: Start cloud-controller-manager
# ============================================
echo "[7/11] Starting cloud-controller-manager..."

# Kill existing CCM if running
sudo pkill -f cloud-controller-manager || true
sleep 2

sudo kubebuilder/bin/cloud-controller-manager \
  --cloud-provider=gce \
  --leader-elect=false \
  --kubeconfig=$HOME/.kube/config \
  --cloud-config=cloud.conf \
  --service-cluster-ip-range=10.0.0.0/24 \
  --cluster-cidr=10.0.0.0/16 \
  --allocate-node-cidrs=true \
  --configure-cloud-routes=true \
  --v=2 &

CCM_PID=$!
echo "Cloud Controller Manager started (PID: $CCM_PID)"
sleep 10

# ============================================
# Step 8: Verify CCM is running
# ============================================
echo "[8/11] Verifying cloud-controller-manager..."
if ps -p $CCM_PID > /dev/null; then
  echo "CCM is running"
else
  echo "CCM failed to start"
  echo "Check logs with: sudo journalctl -xe | grep cloud-controller"
fi

# ============================================
# Step 9: Configure kubelet with provider-id
# ============================================
echo "[9/11] Starting kubelet with provider-id..."
echo ""
echo "Add these parameters to your existing kubelet command:"
echo "  --hostname-override=${INSTANCE_NAME} \\"
echo "  --provider-id=gce://${PROJECT_ID}/${LOCAL_ZONE}/${INSTANCE_NAME} \\"
echo "  --cloud-provider=external \\"
echo ""
echo "Full command example:"
echo "sudo PATH=\$PATH:/opt/cni/bin:/usr/sbin kubebuilder/bin/kubelet \\"
echo "  --kubeconfig=/var/lib/kubelet/kubeconfig \\"
echo "  --config=/var/lib/kubelet/config.yaml \\"
echo "  --root-dir=/var/lib/kubelet \\"
echo "  --cert-dir=/var/lib/kubelet/pki \\"
echo "  --hostname-override=${INSTANCE_NAME} \\"
echo "  --node-ip=\$HOST_IP \\"
echo "  --provider-id=gce://${PROJECT_ID}/${LOCAL_ZONE}/${INSTANCE_NAME} \\"
echo "  --cloud-provider=external \\"
echo "  --v=1 &"
echo ""
echo "Checking current nodes..."
kubectl get nodes -o wide || echo "No nodes found yet"

# ============================================
# Step 10: Deploy test application
# ============================================
echo "[10/11] Deploying test nginx application..."

# Create deployment
kubectl create deployment demo --image=nginx --replicas=1 2>/dev/null || echo "Deployment already exists"

# Wait for deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/demo || echo "Deployment not ready yet"

# Expose as LoadBalancer
kubectl expose deployment demo --type=LoadBalancer --port=80 --name=demo 2>/dev/null || echo "Service already exists"

echo "✅ Test deployment created"

# ============================================
# Step 11: Wait for LoadBalancer IP
# ============================================
echo "[11/11] Waiting for LoadBalancer External IP..."
echo ""

for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  
  if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "null" ]]; then
    echo ""
    echo "=========================================="
    echo "✅ LoadBalancer IP assigned: $EXTERNAL_IP"
    echo "=========================================="
    echo ""
    break
  fi
  
  echo "Waiting for External IP... ($i/30)"
  kubectl get svc demo -o wide
  sleep 10
done

# ============================================
# Summary and verification
# ============================================
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""

echo "Service Status:"
kubectl get svc demo -o wide

echo ""
echo "Pod Status:"
kubectl get pods -l app=demo -o wide

echo ""
echo "Node Status:"
kubectl get nodes -o wide

echo ""
echo "=========================================="
echo "Testing Commands"
echo "=========================================="
echo ""
echo "# Test metadata server - full recursive output:"
echo "curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/\?recursive\=true | jq '.'"
echo ""
echo "# Get project ID:"
echo "curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/project/project-id"
echo ""
echo "# Get service account email:"
echo "curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/email"
echo ""
echo "# Get instance name:"
echo "curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/name"
echo ""
echo "# Get instance ID:"
echo "curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/id"
echo ""
echo "# Check GCP Load Balancer (if real GCP):"
echo "# Open GCP Console → Network Services → Load balancing"
echo "# Look for load balancer with name matching the service"
echo ""
echo "# Test LoadBalancer endpoint:"
echo "EXTERNAL_IP=\$(kubectl get svc demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "curl http://\$EXTERNAL_IP"
echo ""

echo "=========================================="
echo "🛑 Full Cleanup Commands"
echo "=========================================="
echo ""
echo "# 1. Stop local processes:"
echo "sudo pkill -f gce_metadata_server"
echo "sudo pkill -f cloud-controller-manager"
echo ""
echo "# 2. Remove metadata IP:"
echo "sudo ip addr del 169.254.169.254/32 dev lo"
echo ""
echo "# 3. Delete Kubernetes resources:"
echo "kubectl delete svc demo --ignore-not-found"
echo "kubectl delete deployment demo --ignore-not-found"
echo ""
echo "# 4. Delete GCP compute instance (if created):"
echo "gcloud compute instances delete ${INSTANCE_NAME} \\"
echo "  --project=${PROJECT_ID} \\"
echo "  --zone=${LOCAL_ZONE} \\"
echo "  --quiet"
echo ""
echo "# 5. Delete GCP Load Balancers (check in console first):"
echo "# List all forwarding rules:"
echo "gcloud compute forwarding-rules list --project=${PROJECT_ID}"
echo ""
echo "# Delete specific forwarding rule (replace NAME with actual name):"
echo "# gcloud compute forwarding-rules delete FORWARDING_RULE_NAME \\"
echo "#   --region=us-central1 \\"
echo "#   --project=${PROJECT_ID} \\"
echo "#   --quiet"
echo ""
echo "# 6. Remove IAM policy bindings:"
echo "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \\"
echo "  --member='serviceAccount:${SA_EMAIL}' \\"
echo "  --role='roles/compute.instanceAdmin.v1' \\"
echo "  --all"
echo ""
echo "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \\"
echo "  --member='serviceAccount:${SA_EMAIL}' \\"
echo "  --role='roles/compute.networkAdmin' \\"
echo "  --all"
echo ""
echo "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \\"
echo "  --member='serviceAccount:${SA_EMAIL}' \\"
echo "  --role='roles/compute.loadBalancerAdmin' \\"
echo "  --all"
echo ""
echo "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \\"
echo "  --member='serviceAccount:${SA_EMAIL}' \\"
echo "  --role='roles/container.serviceAgent' \\"
echo "  --all"
echo ""
echo "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \\"
echo "  --member='serviceAccount:${SA_EMAIL}' \\"
echo "  --role='roles/iam.serviceAccountUser' \\"
echo "  --all"
echo ""
echo "# 7. Delete service account keys:"
echo "# List keys:"
echo "gcloud iam service-accounts keys list \\"
echo "  --iam-account=${SA_EMAIL} \\"
echo "  --project=${PROJECT_ID}"
echo ""
echo "# Delete specific key (replace KEY_ID with actual ID):"
echo "# gcloud iam service-accounts keys delete KEY_ID \\"
echo "#   --iam-account=${SA_EMAIL} \\"
echo "#   --project=${PROJECT_ID} \\"
echo "#   --quiet"
echo ""
echo "# 8. Delete service account (optional, if no longer needed):"
echo "# gcloud iam service-accounts delete ${SA_EMAIL} \\"
echo "#   --project=${PROJECT_ID} \\"
echo "#   --quiet"
echo ""
echo "# 9. Remove local files:"
echo "rm -f config.json cloud.conf"
echo "rm -f gce_metadata_server/sa.json"
echo "rm -f ../../../gce_metadata_server/sa.json"
echo ""

echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "Process IDs:"
echo "  Metadata Server: ${METADATA_PID:-N/A}"
echo "  Cloud Controller Manager: ${CCM_PID:-N/A}"
echo ""
