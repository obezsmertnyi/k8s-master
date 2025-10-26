#!/usr/bin/env zsh
set -euo pipefail

# - розгорніть control plane
# - створіть debug privileged container з image verizondigital/kubectl-flame:v0.2.4-perf
# - зробіть профілювання kube-apiserver: збір семплів з PID (perf record -F 99 -g -p ...)
# - побудуйте flame graph (perf script -i /tmp/out | FlameGraph/stackcollapse-perf.pl | FlameGraph/flamegraph.pl > flame.svg)
# - скопіюйте flame.svg з контейнера та збережіть у вашому репо

echo "[1/7] Deploying privileged debug pod..."

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: debug-perf
spec:
  hostPID: true
  hostNetwork: true
  restartPolicy: Never
  containers:
  - name: debugger
    image: verizondigital/kubectl-flame:v0.2.4-perf
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
      capabilities:
        add: ["SYS_ADMIN", "SYS_PTRACE"]
EOF

echo "[2/7] Waiting for pod to become Ready..."
kubectl wait --for=condition=Ready pod/debug-perf --timeout=180s

echo "[3/7] Detecting kube-apiserver PID on host..."
# Get PID from host - we need the actual kube-apiserver process, not sudo wrapper
PID=$(ps -ef | grep 'kubebuilder/bin/kube-apiserver' | grep -v sudo | grep -v grep | awk '{print $2}' | head -n1)
if [[ -z "$PID" ]]; then
  echo "kube-apiserver PID not found. Ensure control plane is running."
  exit 1
fi
echo "[i] kube-apiserver PID = $PID"

echo "[4/7] Creating output directory..."
kubectl exec debug-perf -- mkdir -p /tmp

echo "[5/7] Running perf sampling (duration 30s)..."
# Run perf record without -i flag to avoid TTY issues
kubectl exec debug-perf -- /app/perf record -F 99 -g -p "$PID" -o /tmp/out -- sleep 30

echo "[6/7] Building flamegraph from recorded data..."
kubectl exec debug-perf -- sh -c 'cd /tmp && /app/perf script -i out | /app/FlameGraph/stackcollapse-perf.pl | /app/FlameGraph/flamegraph.pl > flame.svg'

echo "[7/7] Copying flame.svg to local directory..."
kubectl cp debug-perf:/tmp/flame.svg ./flame.svg 2>&1 | grep -v "tar: removing leading"

echo ""
echo "[✅] Done!"
echo "Flame graph saved as ./flame.svg"
echo "Open it in your browser to explore CPU usage of kube-apiserver."
echo ""
echo "To clean up the debug pod, run:"
echo "  kubectl delete pod debug-perf"
