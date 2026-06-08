# 📔 Cluster Chronicles: Debugging & Troubleshooting Journal

This document compiles every major bug, configuration mismatch, and resource bottleneck encountered during the final testing and validation of the **Cluster Chronicles** Kubernetes cluster migration. Use this journal as a reference book for debugging similar issues in local Minikube and production Kubernetes environments.

---

## Index of Troubleshooting Logs

1. [Bug 1: Client Browser "Error fetching metrics" (DNS Resolution Mismatch)](#bug-1-client-browser-error-fetching-metrics-dns-resolution-mismatch)
2. [Bug 2: Go Backend Container standard library CVEs (Trivy Scan)](#bug-2-go-backend-container-standard-library-cves-trivy-scan)
3. [Bug 3: Grafana Connection Refused (Grafana Pod OOMKilled)](#bug-3-grafana-connection-refused-grafana-pod-oomkilled)
4. [Bug 4: Custom Application Dashboard "No Data" (Service Scrape Discovery Mismatch)](#bug-4-custom-application-dashboard-no-data-service-scrape-discovery-mismatch)
5. [Bug 5: Kibana 500 Internal Server Error (Elasticsearch Pod OOMKilled)](#bug-5-kibana-500-internal-server-error-elasticsearch-pod-oomkilled)
6. [Bug 6: "Address already in use" Port-Forwarding Lockout](#bug-6-address-already-in-use-port-forwarding-lockout)
7. [Bug 7: stress-ng "Permission denied" on Minikube SSH](#bug-7-stress-ng-permission-denied-on-minikube-ssh)
8. [Bug 8: ResourceQuota Limits Error in `vitals-app` Namespace](#bug-8-resourcequota-limits-error-in-vitals-app-namespace)
9. [Bug 9: Kubernetes Control Plane Freeze & Port-Forward Loss due to CPU Starvation](#bug-9-kubernetes-control-plane-freeze--port-forward-loss-due-to-cpu-starvation)
10. [Bug 10: Kibana Analytics "No logs found" for Application Pods](#bug-10-kibana-analytics-no-logs-found-for-application-pods)
11. [Bug 11: Node Disk Alert (NodeDiskSpaceLow) Not Firing & Missing Mountpoint Filter](#bug-11-node-disk-alert-nodediskspacelow-not-firing--missing-mountpoint-filter)
12. [FAQ: Why are some alerts (etcd, Watchdog, TargetDown) red or firing by default?](#faq-why-are-some-alerts-etcd-watchdog-targetdown-red-or-firing-by-default)

---

## Bug 1: Client Browser "Error fetching metrics" (DNS Resolution Mismatch)

### 1. Symptoms & Context
Opening the web application at `http://vitals.local:8080` loaded the frontend HTML template successfully, but the live system metrics dashboard failed to render, displaying an **"Error fetching metrics"** message.

### 2. Diagnosis & Investigation
* **Command run**:
  ```bash
  kubectl exec -n vitals-app <frontend-pod-name> -- wget -qO- http://vitals-backend-service:8080/health
  # Returns: {"status":"ok"}
  ```
  *(Confirms internal pod-to-pod network connectivity is 100% healthy).*
* **Command run**:
  Open browser Developer Tools Console. Saw errors: `net::ERR_NAME_NOT_RESOLVED` for request `http://vitals-backend-service:8080/metrics`.
* **Root Cause**:
  The frontend UI is an SPA (Single Page Application) that runs client-side JavaScript (`app.js`) inside **your host browser**. The frontend pod's `/config` endpoint returns the internal service address `http://vitals-backend-service:8080`. Your host browser cannot resolve this in-cluster Kubernetes DNS domain name.

### 3. Resolution
1. Modified [ingress.yaml](../manifests/ingress.yaml) to add a second routing rule mapping the host `vitals-backend-service` directly to `vitals-backend-service:8080`.
2. Applied the manifest change:
   ```bash
   kubectl apply -f manifests/ingress.yaml
   ```
3. Added the mapping to the host `/etc/hosts` file:
   ```text
   127.0.0.1 vitals.local vitals-backend-service
   ```
This maps the request to the active `ingress-nginx-controller` port-forward on port 8080, which routes the request inside the cluster.

---

## Bug 2: Go Backend Container standard library CVEs (Trivy Scan)

### 1. Symptoms & Context
Running a manual Trivy security audit on the Go backend docker image returned 16 vulnerabilities (15 High, 1 Critical) inside the compiled binary.

### 2. Diagnosis & Investigation
* **Command run**:
  ```bash
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL vitals-backend:latest
  ```
* **Analysis**:
  Trivy reported **0** OS vulnerabilities for the Alpine base image, but **16** vulnerabilities for the Go standard library binary (`root/backend` gobinary).
* **Root Cause**:
  In `backend/Dockerfile`, the first line used an older Go builder image:
  ```dockerfile
  FROM golang:1.23-alpine AS builder
  ```
  The compiler standard library packages (`crypto/tls`, `net/url`, `crypto/x509`) in Go 1.23 had known CVE vulnerabilities that were compiled directly into the binary.

### 3. Resolution
1. Modified `backend/Dockerfile` to upgrade the build machine to the patched Go 1.24 version:
   ```dockerfile
   FROM golang:1.24-alpine AS builder
   ```
2. Rebuilt the image, synced it to Minikube, and restarted the deployment:
   ```bash
   docker build -t vitals-backend:latest ./backend
   minikube image load vitals-backend:latest
   kubectl rollout restart deployment/vitals-backend -n vitals-app
   ```

---

## Bug 3: Grafana Connection Refused (Grafana Pod OOMKilled)

### 1. Symptoms & Context
Attempting to connect to the Grafana UI on port 9000 returned `Connection refused` in the browser, and the terminal port-forward tunnel exited with `lost connection to pod`.

### 2. Diagnosis & Investigation
* **Command run**:
  ```bash
  kubectl get pods -n monitoring
  # Output: prometheus-grafana-... has RESTARTS 2 (80s ago)
  ```
* **Command run**:
  ```bash
  kubectl describe pod -l app.kubernetes.io/name=grafana -n monitoring
  ```
* **Root Cause**:
  The pod logs indicated Grafana terminated with `Exit Code 137` and `Reason: OOMKilled`. Grafana's memory limit was capped at `250Mi` in the Helm values, which was exceeded when loading heavy dashboard resources.

### 3. Resolution
1. Modified [monitoring-values.yaml](../manifests/monitoring-values.yaml) to increase the Grafana container memory limit to `500Mi`:
   ```yaml
   grafana:
     resources:
       limits:
         cpu: 200m
         memory: 500Mi
   ```
2. Applied the values change by upgrading the Helm deployment:
   ```bash
   helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f manifests/monitoring-values.yaml
   ```

---

## Bug 4: Custom Application Dashboard "No Data" (Service Scrape Discovery Mismatch)

### 1. Symptoms & Context
The automated **Vitals App Custom Dashboard** was imported, but both CPU and Memory graphs showed **"no data"**, indicating Prometheus was not scraping the custom endpoint.

### 2. Diagnosis & Investigation
* **Command run (Querying metrics)**:
  ```bash
  kubectl run tmp-curl-pod --image=curlimages/curl -n monitoring --restart=Never --rm -i -- curl -s "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/query?query=app_cpu_usage_percent"
  # Returns: {"status":"success","data":{"resultType":"vector","result":[]}}
  ```
* **Command run (Querying target health)**:
  We ran a temporary Python container inside the cluster to query Prometheus's targets API and parse the JSON configuration.
  
  **How to execute this inside the cluster**:
  Run a temporary container using `python:3.9-alpine` in the `monitoring` namespace and execute inline Python:
  ```bash
  kubectl run tmp-python-pod --image=python:3.9-alpine -n monitoring --restart=Never --rm -i -- python -c '
  import urllib.request, json
  req = urllib.request.urlopen("http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090/api/v1/targets")
  data = json.loads(req.read().decode())
  dropped = data["data"]["droppedTargets"]
  print(f"Total dropped targets: {len(dropped)}")
  for t in dropped:
      labels = t.get("discoveredLabels", {})
      if "vitals" in labels.get("__meta_kubernetes_service_name", ""):
          print("Found dropped vitals-backend target! Labels:", labels)
  '
  ```
  * **Findings**:
    The service `vitals-backend-service` was listed in the `droppedTargets` list returned by the Prometheus API.
* **Root Cause**:
  The ServiceMonitor `vitals-backend-monitor` filters scrape targets using `spec.selector.matchLabels: app: vitals-backend`. However, in [services.yaml](../manifests/services.yaml), the `vitals-backend-service` metadata had no labels defined. As a result, the ServiceMonitor did not match the service, and Prometheus dropped the target endpoints.

### 3. Resolution
1. Modified [services.yaml](../manifests/services.yaml) to add `app: vitals-backend` to the metadata of the service:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: vitals-backend-service
     namespace: vitals-app
     labels:
       app: vitals-backend
   ```
2. Applied the change:
   ```bash
   kubectl apply -f manifests/services.yaml
   ```

---

## Bug 5: Kibana 500 Internal Server Error (Elasticsearch Pod OOMKilled)

### 1. Symptoms & Context
Opening Kibana at `http://localhost:5601` returned a JSON response: `{"statusCode":500,"error":"Internal Server Error","message":"An internal server error occurred."}`.

### 2. Diagnosis & Investigation
* **Command run**:
  ```bash
  kubectl get pods -n logging
  # Output: elasticsearch-... has RESTARTS 26 (4m22s ago)
  ```
* **Command run**:
  ```bash
  kubectl describe pod -l app=elasticsearch -n logging
  ```
* **Root Cause**:
  Elasticsearch container logs indicated `Exit Code 137` and `Reason: OOMKilled`. The container limit was set to `512Mi`. Since Elasticsearch uses both its 256MB JVM heap and native buffers/Lucene index mapping, it quickly exceeded 512MB and was terminated.

### 3. Resolution
1. Modified [elasticsearch.yaml](../manifests/elasticsearch.yaml) to increase the memory limit to `1Gi` (1024Mi) and the request to `512Mi`:
   ```yaml
   resources:
     requests:
       cpu: 50m
       memory: 512Mi
     limits:
       cpu: 400m
       memory: 1Gi
   ```
2. Applied the updated manifest and restarted Kibana to force a clean reconnection:
   ```bash
   kubectl apply -f manifests/elasticsearch.yaml
   ```

---

## Bug 6: "Address already in use" Port-Forwarding Lockout

### 1. Symptoms & Context
Attempting to restart port-forwards in the terminal failed with errors like: `unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use`.

### 2. Diagnosis & Investigation
* **Root Cause**:
  When the single-node cluster became starved of CPU or restarted, the previous `kubectl port-forward` commands lost connection to the cluster pods but the processes remained alive in the background on the host, locking the local ports.

### 3. Resolution
* Terminated all background port-forwarding processes on the host to release the ports, then restarted the commands:
  ```bash
  killall kubectl
  ```

---

## Bug 7: stress-ng "Permission denied" on Minikube SSH

### 1. Symptoms & Context
Running the disk allocation command `minikube ssh -- fallocate -l 10G /large_file.img` failed with `fallocate: cannot open /large_file.img: Permission denied`.

### 2. Diagnosis & Investigation
* **Root Cause**:
  The `minikube ssh` command logs in as the non-root `docker` user. This user does not have permission to write files directly to the root directory `/`.

### 3. Resolution
* Prepended `sudo` to the command (Minikube's `docker` user runs sudo commands passwordless):
  ```bash
  minikube ssh -- sudo fallocate -l 10G /large_file.img
  ```
  *(And for cleaning up: `minikube ssh -- sudo rm -f /large_file.img`)*

---

## Bug 8: ResourceQuota Limits Error in `vitals-app` Namespace

### 1. Symptoms & Context
Running a temporary load-testing or metric-stressing pod inside the `vitals-app` namespace via:
```bash
kubectl run node-cpu-stress --image=polinux/stress-ng -n vitals-app --restart=Never -- --cpu 4 --timeout 310s
```
Failed with the Kubernetes API Server error:
`Error from server (Forbidden): pods "node-cpu-stress" is forbidden: failed quota: vitals-quota: must specify limits.cpu for: node-cpu-stress; limits.memory for: node-cpu-stress; requests.cpu for: node-cpu-stress; requests.memory for: node-cpu-stress`

### 2. Diagnosis & Investigation
* **Investigation**: Inspected the configuration of the target namespace `vitals-app` using `kubectl describe namespace vitals-app` and listed its resource constraints.
* **Root Cause**: A `ResourceQuota` named `vitals-quota` is deployed in the namespace. This quota enforces that all Pods running inside `vitals-app` must declare explicit container resource requests and limits. Bare `kubectl run` commands omit these defaults, causing the Kubernetes API admission controller to reject the request.

### 3. Resolution
* **Workaround**: Run testing/stressing pods in the `default` namespace (which does not have any active ResourceQuota restrictions):
  ```bash
  kubectl run node-cpu-stress --image=polinux/stress-ng -n default --restart=Never -- --cpu 4 --timeout 310s
  ```
* **Explicit Configuration**: Alternatively, pass resource limits/requests flags using overrides or write a lightweight YAML manifest:
  ```bash
  kubectl run node-cpu-stress --image=polinux/stress-ng -n vitals-app --restart=Never --requests='cpu=100m,memory=128Mi' --limits='cpu=500m,memory=256Mi' -- --cpu 4 --timeout 310s
  ```

---

## Bug 9: Kubernetes Control Plane Freeze & Port-Forward Loss due to CPU Starvation

### 1. Symptoms & Context
While simulating a CPU spike by running `stress-ng --cpu 4` on the Minikube cluster, the Prometheus and Grafana dashboards stopped responding, and all terminal port-forward instances crashed with:
`error: lost connection to pod` or `unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use`.

### 2. Diagnosis & Investigation
* **Investigation**: Checked CPU cores allocated to the Minikube VM using `minikube status`.
* **Root Cause**: The Minikube single-node cluster shares the same CPU cores for both user applications (`vitals-app`) and core Kubernetes system components (`kube-apiserver`, `kubelet`, `kube-proxy`, and `containerd`). Stressing the CPU with 4 threads fully saturated the VM CPU capacity. As a result, critical control plane components starved of CPU, failed health checks, and became unresponsive, severing the port-forward connection.

### 3. Resolution
1. Terminated all locked and orphaned port-forward processes running on the host Mac:
   ```bash
   killall kubectl
   ```
2. Reduced load testing parameters to prevent control plane starvation (e.g. using 1 or 2 threads instead of 4):
   ```bash
   kubectl run node-cpu-stress --image=polinux/stress-ng -n default --restart=Never -- --cpu 2 --timeout 310s
   ```
3. Restarted port-forwards only after the node metrics settled back to normal.

---

## Bug 10: Kibana Analytics "No logs found" for Application Pods

### 1. Symptoms & Context
After deploying Fluent Bit and creating the Kibana index pattern, search queries in Kibana's Discover panel yielded no results for logs from the backend (`vitals-backend`) or frontend (`vitals-frontend`) pods, despite them generating console output.

### 2. Diagnosis & Investigation
* **Investigation**: Reviewed [fluent-bit.yaml](../manifests/fluent-bit.yaml) to inspect where logs are shipped.
* **Findings**: Under the `[OUTPUT]` block, Fluent Bit was configured to prefix indices with `vitals-logs`:
  ```ini
  Logstash_Format On
  Logstash_Prefix vitals-logs
  ```
  This means Elasticsearch indices are created as `vitals-logs-YYYY.MM.DD`. Standard guides suggest creating a generic index pattern (like `logstash-*` or `fluent-bit-*`), which does not capture indices prefixed with `vitals-logs-*`.

### 3. Resolution
* Created a new index pattern specifically matching the custom log prefix configured in Fluent Bit:
  ```text
  vitals-logs-*
  ```
* Set the time filter field to `@timestamp`. Once saved, all application logs from the backend and frontend pods showed up correctly in Kibana under this new pattern.

---

## Bug 11: Node Disk Alert (`NodeDiskSpaceLow`) Not Firing & Missing Mountpoint Filter

### 1. Symptoms & Context
Running `minikube ssh -- sudo fallocate -l 10G /large_file.img` wrote a 10GB file to the VM, but the `NodeDiskSpaceLow` alert in the Prometheus dashboard remained inactive (green) and did not fire. Additionally, querying the PromQL expression:
```query
(node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
```
returned an empty result vector `[]`.

### 2. Diagnosis & Investigation
* **Investigation**:
  * Checked the Minikube disk configuration inside the VM using `df -h`. On macOS (using the Docker driver), the virtual filesystem shares the host Mac's SSD storage, reporting a total disk capacity of ~1TB. A 10GB file only occupies ~1% of that capacity, which fails to trigger the alert rule requiring available space to fall below 20%. Simulating this with a 730GB+ file is dangerous and could crash the host Mac.
  * Checked the metrics exported by Node Exporter inside the Prometheus database. In containerized setups like Minikube, Node Exporter does not report a mountpoint called `/`. Instead, the primary storage volume is mounted under `/data` (or `/etc/hostname`, `/var` etc.). Thus, filtering on `mountpoint="/"` dropped all metrics, causing the expression to return nothing.

### 3. Resolution
1. Updated the rule expression in [prometheus-rules.yaml](../manifests/prometheus-rules.yaml) to match either `/` (for production) or `/data` (for local Minikube) using a regex selector:
   ```yaml
   expr: (node_filesystem_free_bytes{mountpoint=~"/|/data"} / node_filesystem_size_bytes{mountpoint=~"/|/data"}) * 100 < 20
   ```
2. Applied the updated manifest:
   ```bash
   kubectl apply -f manifests/prometheus-rules.yaml
   ```
3. Verified the alert using the **threshold simulation method**:
   * Temporarily raised the threshold to `< 99` and duration to `10s`.
   * Confirmed the alert transitioned to `Firing` in the Prometheus dashboard.
   * Reverted the threshold back to `< 20` and duration to `1m` and re-applied.

---

## FAQ: Why are some alerts (etcd, Watchdog, TargetDown) red or firing by default?

* **Watchdog**: This is an alert that is **permanently firing (red) by design**. It is used to continuously test that the end-to-end alerting pipeline (Prometheus to Alertmanager to notifications) is active and functional. If it stops firing, it indicates the Prometheus rule evaluation engine is broken.
* **etcd alerts (`etcdMembersDown`, `etcdInsufficientMembers`)**: Minikube runs a single-node etcd cluster configured only to bind to loopback/localhost (`127.0.0.1`). The default community Prometheus chart expects a multi-node, clustered etcd setup. Because Prometheus cannot scrape metrics from non-existent peer members, it triggers etcd replication/member alerts. This is normal and safe to ignore in local setups.
* **TargetDown**: Prometheus may report `TargetDown` for control plane components like `kube-controller-manager` or `kube-scheduler`. This happens because these native Kubernetes control plane components bind only to localhost (`127.0.0.1`) on single-node Minikube clusters, preventing Prometheus (which runs in its own network space) from scraping their metrics ports directly.
