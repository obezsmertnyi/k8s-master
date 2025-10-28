# Task 02-4: Build GitOps Loop with Automated Image Updates

**Level:** Basic (Beginners)  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** In Progress

---

## 📋 Overview

This task demonstrates how to build a complete GitOps loop using FluxCD with automated image updates. When a new container image is pushed to a registry, Flux will automatically detect it, update the Kubernetes manifests in Git, and deploy the new version to the cluster.

## 🎯 Learning Objectives

- Understand GitOps principles and workflow
- Install and configure FluxCD in a Kubernetes cluster
- Set up automated image scanning and updates
- Configure Git repository synchronization
- Implement automated deployment pipeline

## 🏗️ Architecture

```
┌─────────────────┐
│  Container      │
│  Registry       │──┐
│  (Docker Hub/   │  │ 1. Push new image
│   GitHub CR)    │  │
└─────────────────┘  │
                     ▼
┌─────────────────────────────────────┐
│  FluxCD Image Automation            │
│  ┌──────────────────────────────┐   │
│  │ ImageRepository              │   │ 2. Scan for new images
│  │ ImagePolicy                  │   │
│  │ ImageUpdateAutomation        │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
                     │
                     │ 3. Update Git repo
                     ▼
┌─────────────────────────────────────┐
│  Git Repository                     │
│  ┌──────────────────────────────┐   │
│  │ deployment.yaml (updated)    │   │
│  │ kustomization.yaml           │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
                     │
                     │ 4. Sync changes
                     ▼
┌─────────────────────────────────────┐
│  Kubernetes Cluster                 │
│  ┌──────────────────────────────┐   │
│  │ FluxCD GitRepository         │   │ 5. Deploy new version
│  │ Kustomization                │   │
│  │ Application Pods             │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## 📦 Prerequisites

- Kubernetes cluster (local with kind/minikube or cloud)
- kubectl configured
- GitHub account and personal access token
- Docker Hub or GitHub Container Registry account
- flux CLI installed

### Install Flux CLI

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installation
flux --version
```

## 🚀 Step-by-Step Implementation

### Step 1: Prepare Git Repository

Create a new GitHub repository for your GitOps configuration:

```bash
# Create a new repository on GitHub (via web UI or gh CLI)
gh repo create flux-gitops-demo --public --clone

cd flux-gitops-demo

# Create directory structure
mkdir -p clusters/dev/apps
mkdir -p apps/demo-app
```

### Step 2: Bootstrap Flux

Bootstrap Flux in your cluster and connect it to your Git repository:

```bash
# Export GitHub credentials
export GITHUB_TOKEN=<your-github-token>
export GITHUB_USER=<your-github-username>

# Bootstrap Flux
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=flux-gitops-demo \
  --branch=main \
  --path=./clusters/dev \
  --personal

# Verify Flux installation
flux check
kubectl get pods -n flux-system
```

### Step 3: Create Demo Application

Create a simple demo application to test the GitOps loop:

```yaml
# apps/demo-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: nginx:1.25.0  # Initial version
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: default
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

```yaml
# apps/demo-app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

### Step 4: Configure Flux to Deploy Application

```yaml
# clusters/dev/apps/demo-app-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: demo-app
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/${GITHUB_USER}/flux-gitops-demo
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: demo-app
  namespace: flux-system
spec:
  interval: 5m
  path: ./apps/demo-app
  prune: true
  sourceRef:
    kind: GitRepository
    name: demo-app
  targetNamespace: default
```

Commit and push:

```bash
git add .
git commit -m "Add demo application"
git push origin main

# Wait for Flux to sync
flux reconcile kustomization demo-app --with-source

# Verify deployment
kubectl get pods -n default
kubectl get svc -n default
```

### Step 5: Configure Image Automation

Install Flux image automation controllers:

```bash
flux install --components-extra=image-reflector-controller,image-automation-controller
```

Create image automation resources:

```yaml
# clusters/dev/apps/demo-app-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: demo-app
  namespace: flux-system
spec:
  image: nginx  # Docker Hub image
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: demo-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: demo-app
  policy:
    semver:
      range: 1.25.x  # Only patch versions of 1.25
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: demo-app
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
      messageTemplate: |
        Automated image update
        
        Automation name: {{ .AutomationObject }}
        
        Files:
        {{ range $filename, $_ := .Updated.Files -}}
        - {{ $filename }}
        {{ end -}}
        
        Objects:
        {{ range $resource, $_ := .Updated.Objects -}}
        - {{ $resource.Kind }} {{ $resource.Name }}
        {{ end -}}
        
        Images:
        {{ range .Updated.Images -}}
        - {{.}}
        {{ end -}}
    push:
      branch: main
  update:
    path: ./apps/demo-app
    strategy: Setters
```

### Step 6: Add Image Update Markers

Update the deployment to include image update markers:

```yaml
# apps/demo-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: nginx:1.25.0  # {"$imagepolicy": "flux-system:demo-app"}
        ports:
        - containerPort: 80
```

Commit and push:

```bash
git add .
git commit -m "Add image automation"
git push origin main

# Reconcile Flux
flux reconcile kustomization flux-system --with-source
```

### Step 7: Verify Automation

Check the image automation status:

```bash
# Check ImageRepository
flux get image repository demo-app

# Check ImagePolicy
flux get image policy demo-app

# Check ImageUpdateAutomation
flux get image update demo-app

# Watch for automatic updates
watch kubectl get pods -n default
```

When a new nginx image matching the policy (e.g., 1.25.1, 1.25.2) is released, Flux will:
1. Detect the new image
2. Update the deployment.yaml in Git
3. Commit the change
4. Deploy the new version to the cluster

## 🧪 Testing the GitOps Loop

### Manual Test with Custom Image

If you want to test with your own image:

1. **Build and push a test image:**

```bash
# Create a simple Dockerfile
cat > Dockerfile <<EOF
FROM nginx:alpine
RUN echo "Version 1.0.0" > /usr/share/nginx/html/index.html
EOF

# Build and tag
docker build -t ${DOCKER_USERNAME}/demo-app:1.0.0 .
docker push ${DOCKER_USERNAME}/demo-app:1.0.0

# Push version 1.0.1
docker build -t ${DOCKER_USERNAME}/demo-app:1.0.1 .
docker push ${DOCKER_USERNAME}/demo-app:1.0.1
```

2. **Update ImageRepository and ImagePolicy:**

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: demo-app
  namespace: flux-system
spec:
  image: ${DOCKER_USERNAME}/demo-app
  interval: 1m
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: demo-app
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: demo-app
  policy:
    semver:
      range: 1.0.x
```

3. **Watch the automation:**

```bash
# Watch Git commits
watch -n 5 'git pull && git log --oneline -5'

# Watch pods
watch kubectl get pods -n default
```

## 📊 Monitoring and Troubleshooting

### Check Flux Status

```bash
# Overall status
flux check

# Component status
kubectl get pods -n flux-system

# Image automation status
flux get images all

# Kustomization status
flux get kustomizations

# Source status
flux get sources all
```

### Common Issues

1. **Image not detected:**
   - Check ImageRepository: `flux get image repository demo-app`
   - Verify registry credentials if using private registry
   - Check image policy range

2. **Git commits not created:**
   - Verify GitHub token has write permissions
   - Check ImageUpdateAutomation logs: `kubectl logs -n flux-system deploy/image-automation-controller`

3. **Deployment not updated:**
   - Check Kustomization status: `flux get kustomization demo-app`
   - Verify image policy marker syntax in deployment.yaml

### View Logs

```bash
# Image reflector controller
kubectl logs -n flux-system deploy/image-reflector-controller -f

# Image automation controller
kubectl logs -n flux-system deploy/image-automation-controller -f

# Kustomize controller
kubectl logs -n flux-system deploy/kustomize-controller -f
```

## 🎓 Key Concepts Learned

1. **GitOps Principles:**
   - Git as single source of truth
   - Declarative infrastructure
   - Automated synchronization

2. **Flux Components:**
   - Source Controller: Manages Git repositories
   - Kustomize Controller: Applies Kubernetes manifests
   - Image Reflector Controller: Scans container registries
   - Image Automation Controller: Updates Git with new images

3. **Image Policies:**
   - Semver: Semantic versioning (1.0.x, ^1.0.0)
   - Alphabetical: Latest alphabetically
   - Numerical: Latest numerically

4. **Automation Flow:**
   - Image scanning → Policy evaluation → Git update → Cluster sync

## 🔄 Next Steps

- **Task 02-5:** Break the GitOps loop and migrate to gitless approach
- Explore advanced Flux features (notifications, multi-tenancy)
- Implement staging and production environments
- Add Helm chart deployments

## 📚 References

- [FluxCD Documentation](https://fluxcd.io/docs/)
- [Image Automation Guide](https://fluxcd.io/flux/guides/image-update/)
- [GitOps Principles](https://opengitops.dev/)
- [Flux Best Practices](https://fluxcd.io/flux/guides/best-practices/)

---

**Status:** ✅ Complete  
**Date:** 2025-01-28
