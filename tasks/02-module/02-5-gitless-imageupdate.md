# Task 02-5: Break GitOps Loop - Migrate to Gitless with Image Updates

**Level:** Advanced (Experienced)  
**Module:** 02 - Custom Kubernetes Controller  
**Status:** Planned

---

## 📋 Overview

This task demonstrates how to break the traditional GitOps loop and migrate to a "gitless" approach while still maintaining automated image updates. Instead of committing image changes back to Git, we'll use Flux's in-cluster state management to handle image updates directly.

## 🎯 Learning Objectives

- Understand limitations of the traditional GitOps loop
- Learn about gitless deployment strategies
- Implement in-cluster image update automation
- Configure Flux without Git write-back
- Solve the image update problem without polluting Git history

## 🤔 Why Break the GitOps Loop?

### Problems with Traditional GitOps + Image Automation:

1. **Git History Pollution:** Every image update creates a commit, cluttering the repository
2. **Merge Conflicts:** Multiple environments updating the same files can cause conflicts
3. **CI/CD Overhead:** Each image update triggers CI pipelines unnecessarily
4. **Audit Trail Noise:** Important infrastructure changes get lost in automated commits
5. **Branch Management:** Difficult to manage with multiple environments and branches

### Gitless Approach Benefits:

- Clean Git history with only intentional changes
- No automated commits from image updates
- Reduced Git repository size
- Simplified branch management
- Faster deployments (no Git round-trip)
- Better separation of concerns (config vs. runtime state)

## 🏗️ Architecture Comparison

### Traditional GitOps (Task 02-4):
```
Image Registry → Flux Image Automation → Git Commit → Flux Sync → Cluster
                                          ↑                          ↓
                                          └──────────────────────────┘
                                          (Circular dependency)
```

### Gitless Approach (This Task):
```
Image Registry → Flux Image Automation → Direct Cluster Update
                                                    ↓
Git Repository → Flux Sync → Base Configuration → Cluster
(Infrastructure only)        (No image tags)
```

## 📦 Prerequisites

- Completed Task 02-4 (GitOps loop with image automation)
- Kubernetes cluster with FluxCD installed
- Understanding of Flux image automation components
- kubectl and flux CLI configured

## 🚀 Step-by-Step Implementation

### Step 1: Understand Current State

Review your existing GitOps setup from Task 02-4:

```bash
# Check current image automation
flux get image repository
flux get image policy
flux get image update

# Review Git commits created by automation
git log --oneline --grep="Automated image update"
```

### Step 2: Disable Git Write-Back

Remove or disable the ImageUpdateAutomation resource:

```bash
# Suspend image update automation
flux suspend image update demo-app

# Or delete it entirely
kubectl delete imageupdateautomation demo-app -n flux-system
```

### Step 3: Modify Deployment Strategy

Update your deployment to use image policy without Git markers:

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
      annotations:
        # Use annotation-based image policy instead of inline markers
        image.toolkit.fluxcd.io/demo-app: nginx
    spec:
      containers:
      - name: demo-app
        image: nginx:latest  # Base image, will be overridden by policy
        ports:
        - containerPort: 80
```

### Step 4: Configure In-Cluster Image Updates

Create a custom Kustomization with image substitution:

```yaml
# clusters/dev/apps/demo-app-kustomization.yaml
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
  # Enable image automation without Git write-back
  images:
    - name: nginx
      newName: nginx
      newTag: 1.25.0  # This will be updated by ImagePolicy
  # Automatically update images based on policies
  patches:
    - patch: |
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: demo-app
        spec:
          template:
            metadata:
              annotations:
                image-policy: flux-system/demo-app
```

### Step 5: Alternative Approach - Use Flux Image Automation with Setters

Configure Flux to update images in-cluster without Git commits:

```yaml
# clusters/dev/apps/demo-app-automation-v2.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: demo-app
  namespace: flux-system
spec:
  image: nginx
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
      range: 1.25.x
---
# Use Kustomization with image substitution instead of ImageUpdateAutomation
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: demo-app
  namespace: flux-system
spec:
  interval: 1m  # Frequent reconciliation for quick updates
  path: ./apps/demo-app
  prune: true
  sourceRef:
    kind: GitRepository
    name: demo-app
  targetNamespace: default
  # Automatically substitute images based on ImagePolicy
  images:
    - name: nginx
      newName: nginx
      # newTag will be automatically set from ImagePolicy
  # Reference the ImagePolicy for automatic updates
  dependsOn:
    - name: demo-app-images
---
# Helper Kustomization to ensure ImagePolicy is ready
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: demo-app-images
  namespace: flux-system
spec:
  interval: 1m
  path: ./clusters/dev/apps
  prune: false
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### Step 6: Implement Custom Controller (Advanced)

For more control, create a custom controller that watches ImagePolicy and updates Deployments:

```go
// controllers/imageupdate_controller.go
package controllers

import (
    "context"
    "fmt"
    
    imagev1 "github.com/fluxcd/image-reflector-controller/api/v1beta2"
    appsv1 "k8s.io/api/apps/v1"
    "k8s.io/apimachinery/pkg/types"
    ctrl "sigs.k8s.io/controller-runtime"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/log"
)

type ImageUpdateReconciler struct {
    client.Client
}

func (r *ImageUpdateReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    logger := log.FromContext(ctx)
    
    // Get ImagePolicy
    var policy imagev1.ImagePolicy
    if err := r.Get(ctx, req.NamespacedName, &policy); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    if policy.Status.LatestImage == "" {
        return ctrl.Result{}, nil
    }
    
    // Find deployments with matching annotation
    var deployments appsv1.DeploymentList
    if err := r.List(ctx, &deployments); err != nil {
        return ctrl.Result{}, err
    }
    
    for _, deploy := range deployments.Items {
        // Check if deployment references this policy
        if policyRef, ok := deploy.Annotations["image-policy"]; ok {
            if policyRef == fmt.Sprintf("%s/%s", policy.Namespace, policy.Name) {
                // Update container image
                for i := range deploy.Spec.Template.Spec.Containers {
                    deploy.Spec.Template.Spec.Containers[i].Image = policy.Status.LatestImage
                }
                
                if err := r.Update(ctx, &deploy); err != nil {
                    logger.Error(err, "Failed to update deployment", "deployment", deploy.Name)
                    return ctrl.Result{}, err
                }
                
                logger.Info("Updated deployment image", 
                    "deployment", deploy.Name,
                    "image", policy.Status.LatestImage)
            }
        }
    }
    
    return ctrl.Result{}, nil
}

func (r *ImageUpdateReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&imagev1.ImagePolicy{}).
        Complete(r)
}
```

### Step 7: Configure RBAC for Custom Controller

```yaml
# config/rbac/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: imageupdate-controller
rules:
- apiGroups: ["image.toolkit.fluxcd.io"]
  resources: ["imagepolicies"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: imageupdate-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: imageupdate-controller
subjects:
- kind: ServiceAccount
  name: imageupdate-controller
  namespace: flux-system
```

### Step 8: Deploy and Test

```bash
# Apply the new configuration
git add .
git commit -m "Migrate to gitless image updates"
git push origin main

# Reconcile Flux
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization demo-app --with-source

# Watch for updates
watch kubectl get pods -n default

# Check that no new Git commits are created
git pull
git log --oneline -5
```

## 🧪 Testing the Gitless Approach

### Test 1: Verify No Git Commits

```bash
# Push a new image version
docker build -t ${DOCKER_USERNAME}/demo-app:1.0.2 .
docker push ${DOCKER_USERNAME}/demo-app:1.0.2

# Wait for Flux to detect and apply
sleep 60

# Check deployment was updated
kubectl get deployment demo-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'

# Verify no new Git commits
git pull
git log --oneline -5 | grep -i "automated"
# Should return nothing
```

### Test 2: Verify Image Updates Work

```bash
# Check ImagePolicy status
flux get image policy demo-app

# Check deployment image
kubectl describe deployment demo-app -n default | grep Image:

# Verify pods are running new version
kubectl get pods -n default -o jsonpath='{.items[*].spec.containers[*].image}'
```

### Test 3: Verify Git Remains Clean

```bash
# Make an intentional change
echo "# Updated docs" >> README.md
git add README.md
git commit -m "Update documentation"
git push origin main

# Verify only intentional commits appear
git log --oneline -10
```

## 📊 Monitoring and Troubleshooting

### Check Image Policy Status

```bash
# View ImagePolicy
kubectl get imagepolicy demo-app -n flux-system -o yaml

# Check latest detected image
kubectl get imagepolicy demo-app -n flux-system -o jsonpath='{.status.latestImage}'
```

### Verify Kustomization Updates

```bash
# Check Kustomization status
flux get kustomization demo-app

# View Kustomization details
kubectl describe kustomization demo-app -n flux-system
```

### Debug Custom Controller (if used)

```bash
# View controller logs
kubectl logs -n flux-system deploy/imageupdate-controller -f

# Check controller status
kubectl get pods -n flux-system -l app=imageupdate-controller
```

## 🎓 Key Concepts Learned

1. **Gitless Deployment:**
   - Separating infrastructure config from runtime state
   - Using Flux's in-cluster image substitution
   - Avoiding Git write-back for automated changes

2. **Image Update Strategies:**
   - Kustomization with image substitution
   - Custom controllers for fine-grained control
   - Annotation-based image policies

3. **Trade-offs:**
   - **Pros:** Clean Git history, faster deployments, no merge conflicts
   - **Cons:** Image versions not tracked in Git, requires different audit approach

4. **Best Practices:**
   - Use Git for infrastructure and configuration
   - Use cluster state for runtime image versions
   - Implement proper monitoring and alerting
   - Document image update strategy clearly

## 🔄 Comparison: GitOps vs Gitless

| Aspect | GitOps (02-4) | Gitless (02-5) |
|--------|---------------|----------------|
| Git Commits | Automated for every image | Only manual changes |
| Git History | Cluttered with automation | Clean and intentional |
| Deployment Speed | Slower (Git round-trip) | Faster (direct update) |
| Audit Trail | In Git | Requires separate logging |
| Rollback | Git revert | Manual or external tool |
| Complexity | Lower | Higher |
| Best For | Small teams, simple apps | Large scale, many images |

## 🔄 Next Steps

- **Task 02-6:** Configure ephemeral environments for GitHub PRs
- Implement proper monitoring for image updates
- Add Slack/Teams notifications for image changes
- Create custom dashboards for image versions
- Explore hybrid approaches (gitless for images, GitOps for config)

## 📚 References

- [Flux Image Automation](https://fluxcd.io/flux/guides/image-update/)
- [Kustomize Image Transformer](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/images/)
- [Flux Best Practices](https://fluxcd.io/flux/guides/best-practices/)
- [GitOps vs Gitless Debate](https://www.weave.works/blog/gitops-without-git)

---

**Status:** 📝 Planned  
**Prerequisites:** Task 02-4 completed
