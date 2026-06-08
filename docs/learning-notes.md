# Cluster Chronicles: DevOps & SRE Study Guide

This document is my own learning notes which captured and documented all the new knowledge, concepts and decision making during this project. It contains all the theoretical concepts, practical command checklists, and interview-critical knowledge that I have learned from this project.

---

## Section A: Core Architectural Concepts (Phases 2 & 3)
### 1. Sherlock Logs vs. Cluster Chronicles
* **In VM-based setups (`sherlock-logs`)**: We managed individual Virtual Machines (App Server, Web Servers) separately. Deploying code required logging into specific machines, installing Docker, mapping host ports manually (e.g., `8080:8080`), and connecting them via hardcoded static IPs (like `192.168.56.14`).
* **In Kubernetes (`cluster-chronicles`)**: We group VMs (nodes) into a single pool of compute power. We don't care *which* node runs our backend container. We tell Kubernetes: *"Run 1 backend and 2 frontends, and make sure they can talk to each other."* Kubernetes handles scheduling, port mapping, self-healing, and routing automatically.

### 2. Kubernetes and Virtual Machines
* Kubernetes **does not replace VMs**; it orchestration-manages them. 
* In cloud environments like AWS (EKS) or GCP (GKE), when we scale our cluster, we are adding EC2 instances or Compute Engine VMs (called **Worker Nodes**).

### 3. Relevance of Foundational OS/Networking Knowledge
* However, working with Kubernetes does not mean you can just forget how Vms works. You **STILL MUST** know how VMs, networking, systemd, SSH, and basic OS performance metrics work. When a Kubernetes Pod fails with a DNS timeout or a network latency issue, it's almost always a Linux networking/IP tables issue under the hood. The VM knowledge makes us a senior troubleshooter, not just a YAML writer.

### 4. Resource Requests vs. Limits
* **Resource Requests**: The *minimum* CPU and Memory (RAM) Kubernetes guarantees to our container. Kubernetes uses this value to decide which node has enough room to run our Pod.
* **Resource Limits**: The *maximum* CPU and Memory our container is allowed to consume.
* **Takeaway for the job**: If our app exceeds its Memory Limit, the Linux kernel terminates the process with an Out Of Memory (OOM) error (Kubernetes shows status `OOMKilled`). If it exceeds its CPU Limit, Kubernetes throttles (slows down) the CPU but doesn't kill it. Setting these correctly prevents a single buggy application from consuming all resources and crashing other apps on the same node ("noisy neighbor" problem).

### 5. Service Discovery & Ephemeral Networking
* In VM environments, the frontend was configured with `BACKEND_URL=http://192.168.56.14:8080`. But in Kubernetes, Pods are ephemeral; they are constantly destroyed and rescheduled, getting brand-new internal IPs every time.
* To solve this, we define a **Service** (specifically a `ClusterIP` service). A Service has a stable IP address and a stable DNS record (e.g., `http://vitals-backend-service:8080`).
* When we define internal networking, we configure the frontend to talk to `vitals-backend-service`. Kubernetes' built-in DNS (CoreDNS) automatically routes requests from the frontend Pod to the backend Service, which then load-balances the traffic across the active backend Pods.

### 6. ConfigMaps vs. Secrets
* **ConfigMap**: A key-value store for non-sensitive configuration data (like `BACKEND_URL` or environment names).
* **Secret**: A key-value store for sensitive data (like database passwords, API tokens, or SSL certificates). Secrets are Base64 encoded by default in Kubernetes (not securely encrypted by default, but it keeps plain-text passwords out of your Git repository).

### 7. Declarative Manifests & GitOps Foundation
* Manifests are declarative YAML files that describe what our infrastructure should look like. Instead of running commands (e.g., `docker run`), we describe the "desired state" (e.g., *"I want a deployment named backend with 1 replica using this image"*), and run `kubectl apply -f manifest.yaml`. Kubernetes continuously reconciles the cluster to match your manifest.

### 8. Pod Statuses & Troubleshooting Lifecycle
* Run `kubectl get pods` to see if the status is `Running` and the `RESTARTS` count is `0`.
* If a Pod is failing, run `kubectl describe pod <pod-name>`. Look at the **Events** section at the bottom. It will tell us if the image name is wrong (`ImagePullBackOff`), if it's waiting for resources (`Pending`), or if the container crashed immediately (`CrashLoopBackOff`).
* Run `kubectl logs <pod-name>` to see the application startup output (stdout/stderr). This is where we verify if our application successfully booted and bound to its port.

### 9. Ingress Controllers (Layer-7 Reverse Proxies)
* A Service of type `ClusterIP` is only reachable inside the cluster. To access the frontend from your Mac's web browser, we need a way to route traffic from outside the cluster inside.
* An **Ingress** resource is a set of rules (like a reverse proxy/NGINX configuration) that routes external HTTP/HTTPS traffic to internal Services based on hostnames (e.g., routing `http://vitals.local/` to the frontend service).

### 10. Validating Internal Communication
* We can exec into an active frontend Pod (`kubectl exec -it <frontend-pod-name> -- sh`) and attempt to ping/curl/wget the backend Service URL (`vitals-backend-service:8080/health`). If it returns a `200 OK`, the internal network is perfectly wired!

### 11. PersistentVolumes (PV) vs. PersistentVolumeClaims (PVC)
* **PersistentVolume (PV)**: A cluster-wide storage resource provisioned by an administrator (or dynamically via a StorageClass). It represents actual storage capacity (disk space) and exists independently of any Pod lifecycle.
* **PersistentVolumeClaim (PVC)**: A request for storage by a user/Pod. Similar to how a Pod consumes node CPU/Memory resources, a PVC consumes PV storage resources. PVC specifies access modes, size, and storage class.
* **Access Modes**:
  * `ReadWriteOnce` (RWO): Mountable read-write by a single node (most common for single database/app instances).
  * `ReadOnlyMany` (ROX): Mountable read-only by many nodes.
  * `ReadWriteMany` (RWX): Mountable read-write by many nodes (requires network file systems like NFS).
* **Reclaim Policies**:
  * `Retain`: When the PVC is deleted, the PV remains intact, preserving the data for manual recovery.
  * `Delete`: When the PVC is deleted, the backing storage (and PV) is automatically wiped out.

### 12. Role-Based Access Control (RBAC): ServiceAccounts & Scopes
* **ServiceAccount**: An identity created inside Kubernetes for processes/applications running *inside* Pods, allowing them to authenticate and execute commands against the Kubernetes API Server.
* **Role vs. ClusterRole**:
  * **Role**: Defines a set of permissions scoped to a **single namespace** (e.g., manage deployments within `vitals-app`).
  * **ClusterRole**: Defines permissions scoped **cluster-wide** (governing resources like nodes, persistent volumes, or across all namespaces).
* **RoleBinding vs. ClusterRoleBinding**:
  * **RoleBinding**: Grants the permissions defined in a Role to a ServiceAccount within a specific namespace.
  * **ClusterRoleBinding**: Grants permissions cluster-wide to a ServiceAccount.
* **Takeaway for the job**: Always follow the *Principle of Least Privilege*. Do not grant cluster-admin access to your CI/CD runner if it only needs to manage deployments inside a single namespace.

### 13. Prometheus Pull Architecture & Scrape Mechanics
* **Pull vs. Push**: Most monitoring systems use a push agent (sending metrics to a server). Prometheus does the opposite: it **pulls (scrapes)** metrics from HTTP endpoints exposed by target containers (e.g. `/prometheus`) at defined intervals.
* **Scrape Target Helpers**:
  * **Node Exporter**: Runs as a DaemonSet on every node, exposing host OS metrics (CPU, disk, memory, network).
  * **Kube-State-Metrics**: Listens to the API server and generates metrics about object statuses (e.g. how many pods are running, pending, or restarted).
  * **ServiceMonitor**: A custom resource introduced by the Prometheus Operator. Instead of manually editing static configuration files, you declare a `ServiceMonitor` mapping labels (e.g., `app: vitals-backend`), and Prometheus automatically discovers and scrapes it.

### 14. Log Aggregation: Scrape, Filter, and Index (Fluent Bit & EFK)
* **Log Flow**: App container stdout → Node system files `/var/log/containers/*.log` → Fluent Bit DaemonSet → Elasticsearch indexing database → Kibana visualization GUI.
* **Log Enrichment**: Fluent Bit mounts node directories, reads json logs, parses them, queries the local kube-apiserver, and enriches the log line with Kubernetes metadata (adds namespace name, pod name, host node name, and labels). This is crucial for filtering logs in Kibana!

### 15. Alert Routing & De-duplication (Alertmanager)
* Prometheus generates alerts based on PromQL rules, but it does **not** send them to users. It ships them to **Alertmanager**.
* Alertmanager manages:
  * **Deduplication / Grouping**: Combines similar alerts (e.g. 5 pods restart in 1 minute) into a single Slack/Email notification to prevent paging storms.
  * **Inhibition**: Suppresses secondary alerts if a parent service is down (e.g. don't fire "Pod Down" alerts if "Node Unreachable" is already active).
  * **Throttling**: Configured via `group_wait` (how long to wait for more alerts before paging), `group_interval` (time between sending groups of alerts), and `repeat_interval` (how long before re-sending an active alert).

### 16. Autoscaling Mechanics (Horizontal Pod Autoscaler - HPA)
* **Metrics Server**: An aggregator of resource usage data in the cluster. It scrapes metrics from the `Summary API` exposed by the Kubelet on each node and exposes them via the Kubernetes Metrics API (e.g. `kubectl top pods`).
* **HPA Algorithm**: HPA periodically queries the Metrics Server for target CPU or Memory metrics. It calculates the desired number of replicas using this formula:
  $$\text{desiredReplicas} = \lceil \text{currentReplicas} \times (\text{currentMetricValue} / \text{desiredMetricValue}) \rceil$$
  *Example*: If you have 2 replicas, current CPU is 80%, and your target is 50%, the desired replicas will be $\lceil 2 \times (80 / 50) \rceil = \lceil 3.2 \rceil = 4$ replicas.
* **Requirements**: HPA *requires* that the target containers declare `resources.requests` in their pod specification, or else Kubernetes won't have a baseline to compute utilization percentages.

### 17. Container Security & Image Vulnerability Scanning (Trivy)
* **What is Vulnerability Scanning?**: Containers are packaged with base operating system layers (alpine, debian, node). These layers contain libraries, compilers, or binaries that might contain known bugs and exploits (Common Vulnerabilities and Exposures - CVEs).
* **Trivy**: A developer-friendly, fast security scanner. It scans the OS packages and application dependencies of your Docker images against vulnerability databases (like NVD).
* **CI/CD Quality Gate**: In real production, we configure Trivy inside our CI/CD runner script with `--exit-code 1`. If Trivy detects high-severity or critical vulnerabilities, it terminates the script with exit code 1, automatically failing the build pipeline and blocking deployment to production.

### 18. Choosing HPA Scaling Thresholds in Production
* **The Flapping Problem**: Setting a CPU utilization threshold too low (e.g., 20%) causes pods to spin up and down constantly as traffic fluctuates. This is called "flapping", which consumes high CPU overhead (spinning up node pools, scheduling, starting up JVM/Node runtimes) and increases cloud compute costs. Setting it too high (e.g., 90%) means existing pods will saturate and fail/lag before new pods can spawn and pass their liveness/readiness probes.
* **Production Best Practice**: Target between **50% and 70%** CPU/Memory utilization. This leaves enough headroom (30-50%) for current pods to absorb immediate traffic bursts while new replicas are spinning up.

### 19. Vulnerability Remediation & The `.trivyignore` File
* In enterprise production, some CVEs discovered by Trivy might have no official fix available yet, or might represent false positives (e.g., a vulnerability in a packet manager tool that you do not execute in your runtime).
* If your pipeline blocks on all HIGH/CRITICAL issues, you'll never be able to deploy updates.
* **Solution**: Create a `.trivyignore` file at your repository's root. List specific CVE IDs (like `CVE-2023-56789`) with an audit reason (e.g., *"Package not utilized in runtime, no risk of execution"*). Trivy will skip these, allowing the pipeline to pass.

### 20. Reducing Vulnerability Footprints: Distroless & Multi-Stage Builds
* The best security practice is not to patch vulnerabilities, but to **remove the software entirely**.
* **Multi-Stage Builds**: Use a heavy build container (e.g., `golang:1.21` or `node:20` which contains tools, compilers, shell, npm) to compile your production code, and then copy *only* the compiled binary/bundle into a clean, empty runtime container.
* **Distroless Images**: Base images (like `gcr.io/distroless/static-debian12`) that contain *no shell (no sh/bash), no packet manager (no apt/apk), and no system tools*. If an attacker exploits a code vulnerability, they cannot execute OS commands, install packages, or start terminal shells. This drops image sizes dramatically and reduces Trivy CVE findings down to zero.

---

## 🛠️ Section B: Phase 2 & 3 Practical Playbook (Commands & Runbook)

### 1. Local Cluster Bootstrapping
* **Command**: `minikube start --driver=docker --cpus=4 --memory=6144`
  * *Why/What*: Initializes a single-node local Kubernetes cluster inside a Docker container (acting as a VM node) with 4 CPUs and 6GB RAM allocated.
* **Command**: `minikube addons enable ingress`
  * *Why/What*: Deploys the Nginx Ingress Controller into the `ingress-nginx` namespace to handle incoming HTTP routes.

### 2. Docker Image Provisioning (Local Registry Sync)
* **Command**: `docker build -t vitals-backend:latest ./backend`
* **Command**: `docker build -t vitals-frontend:latest ./frontend`
  * *Why/What*: Compiles and builds local images on the host Mac.
* **Command**: `minikube image load vitals-backend:latest`
* **Command**: `minikube image load vitals-frontend:latest`
  * *Why/What*: Copies the built images from your Mac’s local Docker daemon into Minikube’s internal container runtime. Without this, Kubernetes will throw an `ErrImagePull` error because it cannot query local docker images directly.

### 3. Applying Declarative Manifests
* **Command**: `kubectl apply -f manifests/namespace.yaml`
  * *Why/What*: Creates the logical boundary `vitals-app` first.
* **Command**: `kubectl apply -f manifests/`
  * *Why/What*: Declaratively schedules all configurations, secrets, services, deployments, and ingress rules defined in the directory.

### 4. Verification & Observability Runbook
* **Command**: `kubectl get pods -n vitals-app`
  * *Why/What*: Lists pod health. Expect `Running` and `1/1` under the `READY` column.
* **Command**: `kubectl logs -l app=vitals-backend -n vitals-app`
* **Command**: `kubectl logs -l app=vitals-frontend -n vitals-app`
  * *Why/What*: Streams stdout/stderr from backend/frontend pods to ensure the apps booted without error.
* **Command**: `kubectl exec -n vitals-app <frontend-pod-name> -- wget -qO- http://vitals-backend-service:8080/health`
  * *Why/What*: Validates internal DNS and service discovery. If it returns `{"status":"ok"}`, the communication is healthy.
* **Command**: `kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80`
  * *Why/What*: Binds host port `8080` to the Ingress controller’s port `80` (avoids requiring `sudo` on macOS).
* **Command**: `curl -H "Host: vitals.local" http://localhost:8080/config`
  * *Why/What*: Sends a request targeting `vitals.local` hostname directly into the Ingress routing tables.

### 5. Persistent Storage & Volume Claim Validation
* **Command**: `kubectl apply -f manifests/storage.yaml`
  * *Why/What*: Declares the PersistentVolume (`jenkins-pv`) and PersistentVolumeClaim (`jenkins-pvc`) inside the cluster.
* **Command**: `kubectl get pv,pvc -n vitals-app`
  * *Why/What*: Checks the storage binding status. Both should display `Bound` status.

### 6. CI/CD & RBAC Execution
* **Command**: `kubectl apply -f manifests/cicd-rbac.yaml -f manifests/cicd-deployment.yaml`
  * *Why/What*: Deploys the Jenkins service account, namespace role/binding, and the Jenkins deployment with local storage mounted.
* **Command**: `kubectl auth can-i create deployment --as=system:serviceaccount:vitals-app:jenkins-sa -n vitals-app`
  * *Why/What*: Validates that the Jenkins ServiceAccount has permission to create deployments inside the `vitals-app` namespace (should return `yes`).
* **Command**: `kubectl auth can-i create deployment --as=system:serviceaccount:vitals-app:jenkins-sa -n default`
  * *Why/What*: Validates that the Jenkins ServiceAccount is correctly blocked from modifying other namespaces (should return `no`).

### 7. Observability Stack Bootstrapping
* **Command**: `helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update`
  * *Why/What*: Adds and syncs the official Helm repo for the Prometheus Operator stack.
* **Command**: `helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f manifests/monitoring-values.yaml`
  * *Why/What*: Installs Prometheus, Grafana, Alertmanager, Node-Exporter, and Kube-State-Metrics with strict resource allocations to conserve Mac memory.
* **Command**: `kubectl apply -f manifests/prometheus-rules.yaml -f manifests/servicemonitor.yaml`
  * *Why/What*: Deploys custom alerting rules and the target scraping configuration for the Go backend application.
* **Command**: `kubectl apply -f manifests/elasticsearch.yaml -f manifests/fluent-bit.yaml -f manifests/kibana.yaml`
  * *Why/What*: Installs our lightweight EFK logging stack (Fluent Bit forwarding pod logs to Elasticsearch, visualized by Kibana).

### 8. Observability Port-Forward Access
* **Command**: `kubectl port-forward -n monitoring svc/prometheus-grafana 9000:80`
  * *Why/What*: Access Grafana UI at `http://localhost:9000` (default user `admin`, password retrieved via: `kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo`).
* **Command**: `kubectl port-forward -n logging svc/kibana-service 5601:5601`
  * *Why/What*: Access Kibana Log viewer UI at `http://localhost:5601`.
* **Command**: `kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090`
  * *Why/What*: Access raw Prometheus query compiler at `http://localhost:9090`.

### 9. Metrics Server & Autoscaling (HPA)
* **Command**: `minikube addons enable metrics-server`
  * *Why/What*: Deploys the Metrics Server agent inside the cluster to gather node/pod CPU and memory utilization data.
* **Command**: `kubectl apply -f manifests/hpa.yaml`
  * *Why/What*: Declares the HorizontalPodAutoscaler pointing to the `vitals-frontend` deployment.
* **Command**: `kubectl get hpa -n vitals-app`
  * *Why/What*: Retrieves the scaling status, targets, replica counts, and current CPU metrics.

### 10. Security Pipeline Operations (Trivy)
* **Execution**: Trivy is integrated natively as a build stage container inside [Jenkinsfile.k8s](file:///Users/williamle/my_cloud_project/kood-sisu/cluster-chronicles/Jenkinsfile.k8s).
* **Command (inside build container)**: `trivy image --severity HIGH,CRITICAL vitals-backend:latest`
  * *Why/What*: Scans local Docker image layers, compiling a CVE vulnerability list.

---
