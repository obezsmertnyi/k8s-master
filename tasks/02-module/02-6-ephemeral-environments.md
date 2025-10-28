# Task 02-6: Configure Ephemeral Environments for GitHub Pull Requests

**Level:** Expert (Advanced)  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** Planned

---

## 📋 Overview

This task demonstrates how to configure ephemeral (temporary) environments that are automatically created for GitHub Pull Requests using Flux Operator and ResourceSets. Each PR gets its own isolated environment that is automatically destroyed when the PR is closed or merged.

## 🎯 Learning Objectives

- Understand ephemeral environment concepts
- Configure Flux Operator with ResourceSets
- Implement PR-based environment automation
- Set up GitHub webhooks for PR events
- Manage resource lifecycle automatically
- Implement environment cleanup strategies

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Repository                                      │
│  ┌────────────────────────────────────────────────┐    │
│  │  Pull Request #123                             │    │
│  │  - Branch: feature/new-feature                 │    │
│  │  - Status: Open                                │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Webhook Event
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Flux Operator (Control Plane)                         │
│  ┌────────────────────────────────────────────────┐    │
│  │  ResourceSet Controller                        │    │
│  │  - Watches GitHub PR events                    │    │
│  │  - Creates/Deletes FluxInstance                │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Creates FluxInstance
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                     │
│  ┌────────────────────────────────────────────────┐    │
│  │  Namespace: pr-123                             │    │
│  │  ┌──────────────────────────────────────────┐  │    │
│  │  │  FluxInstance                            │  │    │
│  │  │  - GitRepository (PR branch)             │  │    │
│  │  │  - Kustomization                         │  │    │
│  │  │  - Application Deployment                │  │    │
│  │  │  - Service + Ingress                     │  │    │
│  │  └──────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Accessible via
                          ▼
              https://pr-123.example.com
```

## 📦 Prerequisites

- Kubernetes cluster (with sufficient resources for multiple environments)
- Flux CLI installed
- GitHub repository with admin access
- Domain name for PR environments (with wildcard DNS)
- Ingress controller (nginx, traefik, etc.)
- cert-manager for TLS certificates (optional)
- GitHub Personal Access Token with repo permissions

## 🚀 Step-by-Step Implementation

### Step 1: Install Flux Operator

Install the Flux Operator which provides the ResourceSet functionality:

```bash
# Install Flux Operator
flux install --components-extra=flux-operator

# Verify installation
kubectl get pods -n flux-system | grep flux-operator
```

Alternatively, install using Helm:

```bash
helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
helm repo update

helm install flux-operator fluxcd-community/flux-operator \
  --namespace flux-system \
  --create-namespace
```

### Step 2: Configure GitHub Webhook

Create a webhook secret:

```bash
# Generate a random webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 20)

# Create Kubernetes secret
kubectl create secret generic github-webhook \
  --from-literal=token=${WEBHOOK_SECRET} \
  -n flux-system
```

Configure GitHub webhook in your repository:
- Go to Settings → Webhooks → Add webhook
- Payload URL: `https://your-cluster.example.com/webhook`
- Content type: `application/json`
- Secret: Use the `WEBHOOK_SECRET` generated above
- Events: Select "Pull requests" and "Push"

### Step 3: Create ResourceSet for Pull Requests

Create a ResourceSet that watches for GitHub PR events:

```yaml
# clusters/production/flux-operator/pr-resourceset.yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: github-pull-requests
  namespace: flux-system
spec:
  # Watch for GitHub pull request events
  sources:
    - kind: GitHubRepository
      name: demo-app
      namespace: flux-system
  
  # Template for creating ephemeral environments
  template:
    metadata:
      # Create namespace per PR
      name: pr-{{ .PullRequest.Number }}
      labels:
        pr-number: "{{ .PullRequest.Number }}"
        pr-author: "{{ .PullRequest.User.Login }}"
        environment: ephemeral
    
    spec:
      # FluxInstance configuration
      interval: 1m
      
      # Source configuration - use PR branch
      source:
        kind: GitRepository
        name: demo-app-pr-{{ .PullRequest.Number }}
        namespace: pr-{{ .PullRequest.Number }}
        spec:
          interval: 1m
          url: https://github.com/{{ .Repository.FullName }}
          ref:
            branch: "{{ .PullRequest.Head.Ref }}"
          secretRef:
            name: github-token
      
      # Kustomization configuration
      kustomization:
        - name: demo-app
          path: ./apps/demo-app
          prune: true
          targetNamespace: pr-{{ .PullRequest.Number }}
          patches:
            # Patch ingress hostname for this PR
            - patch: |
                apiVersion: networking.k8s.io/v1
                kind: Ingress
                metadata:
                  name: demo-app
                spec:
                  rules:
                    - host: pr-{{ .PullRequest.Number }}.example.com
              target:
                kind: Ingress
                name: demo-app
            
            # Patch deployment with PR-specific labels
            - patch: |
                apiVersion: apps/v1
                kind: Deployment
                metadata:
                  name: demo-app
                  labels:
                    pr-number: "{{ .PullRequest.Number }}"
                spec:
                  template:
                    metadata:
                      labels:
                        pr-number: "{{ .PullRequest.Number }}"
              target:
                kind: Deployment
                name: demo-app
  
  # Cleanup policy
  cleanup:
    # Delete environment when PR is closed or merged
    on:
      - closed
      - merged
    # Grace period before deletion (optional)
    gracePeriod: 5m
  
  # Resource limits per environment
  resources:
    limits:
      cpu: "1"
      memory: 1Gi
    requests:
      cpu: 100m
      memory: 128Mi
```

### Step 4: Configure GitHub Repository Source

```yaml
# clusters/production/flux-operator/github-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitHubRepository
metadata:
  name: demo-app
  namespace: flux-system
spec:
  # GitHub repository
  owner: your-username
  repository: demo-app
  
  # Authentication
  secretRef:
    name: github-token
  
  # Webhook configuration
  webhook:
    secretRef:
      name: github-webhook
    # Expose webhook endpoint
    ingress:
      enabled: true
      className: nginx
      hosts:
        - host: webhook.example.com
          paths:
            - path: /
              pathType: Prefix
---
apiVersion: v1
kind: Secret
metadata:
  name: github-token
  namespace: flux-system
type: Opaque
stringData:
  token: ghp_your_github_personal_access_token
```

### Step 5: Create Base Application Configuration

Prepare your application with environment-specific overrides:

```yaml
# apps/demo-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
spec:
  replicas: 1  # Lower replicas for PR environments
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
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: ENVIRONMENT
          value: "ephemeral"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
spec:
  selector:
    app: demo-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - pr-*.example.com
    secretName: pr-tls
  rules:
  - host: pr-placeholder.example.com  # Will be patched by ResourceSet
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: demo-app
            port:
              number: 80
```

### Step 6: Configure DNS Wildcard

Set up wildcard DNS for PR environments:

```bash
# Add wildcard DNS record
# *.example.com → Your cluster ingress IP

# Or using external-dns (automated)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "*.example.com"
spec:
  type: LoadBalancer
  # ... rest of ingress service config
EOF
```

### Step 7: Set Up Automatic PR Comments

Create a GitHub Action to comment on PRs with environment URL:

```yaml
# .github/workflows/pr-environment.yaml
name: PR Environment

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  comment:
    runs-on: ubuntu-latest
    steps:
      - name: Comment PR
        uses: actions/github-script@v7
        with:
          script: |
            const prNumber = context.issue.number;
            const envUrl = `https://pr-${prNumber}.example.com`;
            
            github.rest.issues.createComment({
              issue_number: prNumber,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🚀 **Ephemeral Environment Ready!**
              
              Your PR environment is available at: ${envUrl}
              
              This environment will be automatically deleted when the PR is closed or merged.
              
              **Environment Details:**
              - Namespace: \`pr-${prNumber}\`
              - Branch: \`${context.payload.pull_request.head.ref}\`
              - Commit: \`${context.payload.pull_request.head.sha.substring(0, 7)}\`
              
              To check the deployment status:
              \`\`\`bash
              kubectl get pods -n pr-${prNumber}
              flux get kustomizations -n pr-${prNumber}
              \`\`\`
              `
            });
```

### Step 8: Implement Resource Quotas

Protect your cluster from resource exhaustion:

```yaml
# clusters/production/flux-operator/pr-resource-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: pr-environment-quota
  namespace: pr-*  # Applied to all PR namespaces
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    limits.cpu: "2"
    limits.memory: 2Gi
    pods: "10"
    services: "5"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: pr-environment-limits
  namespace: pr-*
spec:
  limits:
  - max:
      cpu: "1"
      memory: 1Gi
    min:
      cpu: 10m
      memory: 16Mi
    type: Container
```

### Step 9: Deploy and Test

```bash
# Apply all configurations
git add .
git commit -m "Add ephemeral environment configuration"
git push origin main

# Reconcile Flux
flux reconcile kustomization flux-system --with-source

# Verify ResourceSet is created
kubectl get resourceset -n flux-system

# Create a test PR
git checkout -b feature/test-ephemeral
echo "Test change" >> README.md
git add README.md
git commit -m "Test ephemeral environment"
git push origin feature/test-ephemeral

# Create PR via GitHub UI or gh CLI
gh pr create --title "Test Ephemeral Environment" --body "Testing PR environments"

# Wait for environment to be created
watch kubectl get namespaces | grep pr-

# Check FluxInstance
kubectl get fluxinstance -A

# Verify deployment
PR_NUMBER=$(gh pr list --json number --jq '.[0].number')
kubectl get pods -n pr-${PR_NUMBER}

# Access the environment
curl https://pr-${PR_NUMBER}.example.com
```

## 🧪 Testing Scenarios

### Test 1: PR Creation

```bash
# Create a new PR
gh pr create --title "Feature X" --body "Implementing feature X"

# Wait for environment
sleep 30

# Check namespace created
kubectl get ns | grep pr-

# Verify pods running
kubectl get pods -n pr-$(gh pr list --json number --jq '.[0].number')
```

### Test 2: PR Update

```bash
# Make changes to PR branch
git checkout feature/test-ephemeral
echo "Updated" >> test.txt
git add test.txt
git commit -m "Update feature"
git push origin feature/test-ephemeral

# Wait for Flux to sync
sleep 30

# Verify deployment updated
kubectl describe deployment -n pr-$(gh pr list --json number --jq '.[0].number')
```

### Test 3: PR Closure

```bash
# Close or merge PR
gh pr close $(gh pr list --json number --jq '.[0].number')

# Wait for cleanup (grace period + deletion)
sleep 360

# Verify namespace deleted
kubectl get ns | grep pr-
# Should return nothing
```

## 📊 Monitoring and Troubleshooting

### Check ResourceSet Status

```bash
# View ResourceSet
kubectl get resourceset github-pull-requests -n flux-system -o yaml

# Check ResourceSet controller logs
kubectl logs -n flux-system deploy/flux-operator -f
```

### Monitor Ephemeral Environments

```bash
# List all PR environments
kubectl get ns -l environment=ephemeral

# Check resource usage
kubectl top pods -A -l environment=ephemeral

# View all FluxInstances
kubectl get fluxinstance -A
```

### Debug Webhook Issues

```bash
# Check webhook secret
kubectl get secret github-webhook -n flux-system

# View ingress for webhook
kubectl get ingress -n flux-system

# Test webhook endpoint
curl -X POST https://webhook.example.com/webhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: pull_request" \
  -d '{"action":"opened","number":123}'
```

### Common Issues

1. **Environment not created:**
   - Check webhook is configured correctly in GitHub
   - Verify ResourceSet controller is running
   - Check GitHub token permissions

2. **Environment not deleted:**
   - Verify cleanup policy in ResourceSet
   - Check grace period hasn't expired yet
   - Review ResourceSet controller logs

3. **DNS not resolving:**
   - Verify wildcard DNS record
   - Check ingress controller configuration
   - Ensure cert-manager is working (if using TLS)

## 🎓 Key Concepts Learned

1. **Ephemeral Environments:**
   - Temporary, isolated environments per PR
   - Automatic creation and deletion
   - Resource-efficient testing

2. **Flux Operator:**
   - ResourceSet for dynamic environment management
   - FluxInstance for per-environment Flux installation
   - Template-based configuration

3. **GitHub Integration:**
   - Webhook-driven automation
   - PR event handling
   - Automated PR comments

4. **Resource Management:**
   - Resource quotas per environment
   - Limit ranges for containers
   - Cleanup policies

5. **Best Practices:**
   - Wildcard DNS for dynamic subdomains
   - Resource limits to prevent exhaustion
   - Automated cleanup to save costs
   - PR comments for visibility

## 💡 Advanced Features

### Multi-Cluster Support

Deploy PR environments to different clusters:

```yaml
spec:
  clusters:
    - name: dev-cluster
      kubeconfig:
        secretRef:
          name: dev-cluster-kubeconfig
```

### Database Per Environment

Include database provisioning:

```yaml
spec:
  kustomization:
    - name: database
      path: ./database
      patches:
        - patch: |
            apiVersion: v1
            kind: Secret
            metadata:
              name: db-credentials
            stringData:
              database: pr_{{ .PullRequest.Number }}
```

### Cost Tracking

Add labels for cost allocation:

```yaml
metadata:
  labels:
    cost-center: "engineering"
    pr-number: "{{ .PullRequest.Number }}"
    pr-author: "{{ .PullRequest.User.Login }}"
```

## 🔄 Next Steps

- Implement multi-cluster ephemeral environments
- Add database provisioning per PR
- Set up cost tracking and reporting
- Implement environment hibernation for inactive PRs
- Add smoke tests that run automatically
- Configure Slack/Teams notifications

## 📚 References

- [Flux Operator Documentation](https://fluxcd.control-plane.io/operator/)
- [ResourceSets for GitHub PRs](https://fluxcd.control-plane.io/operator/resourcesets/github-pull-requests/)
- [Ephemeral Environments Best Practices](https://www.weave.works/blog/ephemeral-environments)
- [GitHub Webhooks](https://docs.github.com/en/webhooks)

---

**Status:** 📝 Planned  
**Prerequisites:** Tasks 02-4 and 02-5 completed  
**Estimated Time:** 4-6 hours
