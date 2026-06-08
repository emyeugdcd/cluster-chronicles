# Kubernetes Alerting Verification Guide: Step-by-Step

This document provides step-by-step instructions to safely trigger and verify each of the custom Prometheus alerting rules defined in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) without disrupting the local Minikube cluster.

---

## Index of Testing Steps

1. [Alert 1: Node CPU Usage High (`NodeCPUUsageHigh`)](#alert-1-node-cpu-usage-high-nodecpuusagehigh)
2. [Alert 2: Node Disk Space Low (`NodeDiskSpaceLow`)](#alert-2-node-disk-space-low-nodediskspacelow)
3. [Alert 3: Node Memory Usage High (`NodeMemoryUsageHigh`)](#alert-3-node-memory-usage-high-nodememoryusagehigh)
4. [Alert 4: Pod Frequently Restarting (`PodFrequentlyRestarting`)](#alert-4-pod-frequently-restarting-podfrequentlyrestarting)
5. [Alert 5: Pod Memory Limit Exceeded (`PodMemoryLimitExceeded`)](#alert-5-pod-memory-limit-exceeded-podmemorylimitexceeded)
6. [Alert 6: Pod Stuck in Pending State (`PodStuckInPending`)](#alert-6-pod-stuck-in-pending-state-podstuckinpending)
7. [Alert 7: Kubernetes API Server Down (`KubernetesAPIServerDown`)](#alert-7-kubernetes-api-server-down-kubernetesapiserverdown)

---

## Alert 1: Node CPU Usage High (`NodeCPUUsageHigh`)

* **Objective**: Safely trigger the alert without saturating the Minikube VM's 12-core CPU.
* **Alert Expression**: `100 - (avg by(node) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80` (`for: 5m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily lower the CPU threshold to `> 10` and duration to `10s`:
   ```yaml
   - alert: NodeCPUUsageHigh
     expr: 100 - (avg by(node) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 10
     for: 10s
   ```
2. Apply the rule changes to the cluster:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Run a safe, lightweight 2-core CPU stress container in the `default` namespace (to bypass `vitals-app` ResourceQuotas) for 60 seconds:
   ```bash
   kubectl run node-cpu-stress --image=polinux/stress-ng -n default --restart=Never -- --cpu 2 --timeout 60s
   ```
4. Query the Prometheus alerts API or view the UI at `http://localhost:9191` to verify it transitions to **`firing`**:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep NodeCPUUsageHigh
   ```
5. **Cleanup & Revert**:
   * Revert the threshold in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `> 80` and duration to `5m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.
   * Delete the stress pod: `kubectl delete pod node-cpu-stress -n default`.

---

## Alert 2: Node Disk Space Low (`NodeDiskSpaceLow`)

* **Objective**: Test the low disk alert safely. (Minikube shares your host Mac's SSD, so allocating 10GB will not trigger a `<20%` free space alert, and writing 700GB+ will crash your host).
* **Alert Expression**: `(node_filesystem_free_bytes{mountpoint=~"/|/data"} / node_filesystem_size_bytes{mountpoint=~"/|/data"}) * 100 < 20` (`for: 1m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily raise the free disk threshold to `< 99` and duration to `10s`:
   ```yaml
   - alert: NodeDiskSpaceLow
     expr: (node_filesystem_free_bytes{mountpoint=~"/|/data"} / node_filesystem_size_bytes{mountpoint=~"/|/data"}) * 100 < 99
     for: 10s
   ```
2. Apply the rule changes to the cluster:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Since your current free disk space is ~98.5%, the alert will immediately transition to `Pending` and then **`firing`** without writing any dummy files. Query active alerts:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep NodeDiskSpaceLow
   ```
4. **Cleanup & Revert**:
   * Revert the threshold in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `< 20` and duration to `1m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.

---

## Alert 3: Node Memory Usage High (`NodeMemoryUsageHigh`)

* **Objective**: Safely trigger node memory alert using current idle baseline (~60%).
* **Alert Expression**: `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90` (`for: 5m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily lower the memory threshold to `> 50` and duration to `10s`:
   ```yaml
   - alert: NodeMemoryUsageHigh
     expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 50
     for: 10s
   ```
2. Apply the rule changes to the cluster:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Since your VM memory usage is already ~60%, the alert will fire immediately. Query active alerts to verify:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep NodeMemoryUsageHigh
   ```
4. **Cleanup & Revert**:
   * Revert the threshold in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `> 90` and duration to `5m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.

---

## Alert 4: Pod Frequently Restarting (`PodFrequentlyRestarting`)

* **Objective**: Trigger a pod restart alert bypassing container runtime restart backing-off delays.
* **Alert Expression**: `increase(kube_pod_container_status_restarts_total[15m]) > 3` (`for: 1m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily lower the restart count threshold to `> 1` and duration to `10s`:
   ```yaml
   - alert: PodFrequentlyRestarting
     expr: increase(kube_pod_container_status_restarts_total[15m]) > 1
     for: 10s
   ```
2. Apply the rule changes:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Deploy a crash-looping pod in the `default` namespace (to bypass `vitals-app` ResourceQuotas) with a restart policy of `Always`:
   ```bash
   kubectl run crashy-pod --image=alpine -n default -- /bin/sh -c "sleep 5; exit 1"
   ```
4. Wait 30 seconds for the pod to crash and restart at least twice, then verify the alert transitions to **`firing`**:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep PodFrequentlyRestarting
   ```
5. **Cleanup & Revert**:
   * Delete the crash pod: `kubectl delete pod crashy-pod -n default`.
   * Revert the threshold in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `> 3` and duration to `1m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.

---

## Alert 5: Pod Memory Limit Exceeded (`PodMemoryLimitExceeded`)

* **Objective**: Safely trigger memory limit alerts on active pods.
* **Alert Expression**: `container_memory_working_set_bytes / on(pod) group_left() kube_pod_container_resource_limits{resource="memory"} * 100 > 80` (`for: 5m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily lower the threshold to `> 30` and duration to `10s`:
   ```yaml
   - alert: PodMemoryLimitExceeded
     expr: container_memory_working_set_bytes / on(pod) group_left() kube_pod_container_resource_limits{resource="memory"} * 100 > 30
     for: 10s
   ```
2. Apply the rule changes:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Verify the alert triggers immediately on standard active pods (such as CoreDNS or Grafana) which already use over 30% of their memory limit:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep PodMemoryLimitExceeded
   ```
4. **Cleanup & Revert**:
   * Revert the threshold in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `> 80` and duration to `5m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.

---

## Alert 6: Pod Stuck in Pending State (`PodStuckInPending`)

* **Objective**: Force a pod into Pending state safely.
* **Alert Expression**: `kube_pod_status_phase{phase="Pending"} == 1` (`for: 5m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to temporarily lower the pending duration to `10s`:
   ```yaml
   - alert: PodStuckInPending
     expr: kube_pod_status_phase{phase="Pending"} == 1
     for: 10s
   ```
2. Apply the rule changes:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Run a pod requesting more memory than the cluster can allocate (e.g. `128Gi`) in the `default` namespace (to bypass `vitals-app` ResourceQuotas):
   ```bash
   kubectl run pending-pod --image=nginx -n default --restart=Never --overrides='{"spec":{"containers":[{"name":"pending-container","image":"nginx","resources":{"requests":{"memory":"128Gi"}}}]}}'
   ```
4. Check the pod status to confirm it remains in `Pending` state:
   ```bash
   kubectl get pod pending-pod -n default
   ```
5. Wait 15 seconds and verify the alert transitions to **`firing`**:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep PodStuckInPending
   ```
6. **Cleanup & Revert**:
   * Delete the pending pod: `kubectl delete pod pending-pod -n default`.
   * Revert the duration in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `5m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.

---

## Alert 7: Kubernetes API Server Down (`KubernetesAPIServerDown`)

* **Objective**: Safely trigger API Server alert without actually shutting down the `kube-apiserver` (which would disconnect your CLI and crash port-forward connections).
* **Alert Expression**: `absent(up{job="apiserver"})` (`for: 1m`)

### Verification Procedure
1. Edit [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to check for a non-existent job, like `apiserver-does-not-exist`, and lower duration to `10s`:
   ```yaml
   - alert: KubernetesAPIServerDown
     expr: absent(up{job="apiserver-does-not-exist"})
     for: 10s
   ```
2. Apply the rule changes:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Since this job does not exist, the metric is absent, which instantly triggers the alert:
   ```bash
   curl -s "http://localhost:9191/api/v1/alerts" | grep KubernetesAPIServerDown
   ```
4. **Cleanup & Revert**:
   * Revert the expression in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) back to `absent(up{job="apiserver"})` and duration to `1m`.
   * Re-apply: `kubectl apply -f manifests/prometheus-rules.yaml`.
