# Master Walkthrough & Timeline Diary: Kubernetes Migration & Observability

If you ever wonder how we built this entire Kubernetes cluster from scratch, check out this document which records the exact step-by-step timeline of `cluster-chronicles` project migration from `sherlock-logs` project, including cluster bootstrapping, setting up persistent storage, CI/CD with RBAC, and memory-optimized observability. 

This document serves as a personal guide for myself for if I want to build a Kubernetes cluster from scratch again in the future. It is meant to be a reference that someone can pick up and understand the entire process without having to read every single line of code or every single command. It is also meant to be a reference for if someone wants to build a Kubernetes cluster from scratch and wants to know what to do and what not to do.

---

## Step 1: Cluster Bootstrapping (Phase 1)
* **What I did**: Started a local Minikube cluster using Docker containers as nodes, and enabled Ingress.
* **Commands run**:
  ```bash
  minikube start --driver=docker --cpus=4 --memory=6144
  minikube addons enable ingress
  ```
* **Wait times**:
  * Minikube base image (`kicbase`) download: **~3 minutes** (depending on network speeds).
  * Ingress controller image pulling and verification: **~2 minutes** (Minikube pulls Nginx Controller v1.14.3 and certgen images).

* **Verification**:
  * Checked node status: `kubectl get nodes` (shows `minikube Ready`).
  * Checked ingress: `kubectl get pods -n ingress-nginx` (shows controller pod is `Running`).

---

## Step 2: Containerization & Registry Sync (Phase 2)
* **What I did**: Compiled and built Docker containers on the host machine, then loaded them into the cluster since Minikube cannot access local host docker caches by default.
* **Commands run**:
  ```bash
  # Build backend
  docker build -t vitals-backend:latest ./backend
  # Build frontend
  docker build -t vitals-frontend:latest ./frontend
  
  # Sync to Minikube
  minikube image load vitals-backend:latest
  minikube image load vitals-frontend:latest
  ```
* **Wait times**:
  * Backend compile & build: **~8 seconds** (compiled Go binary).
  * Frontend npm install & build: **~5 seconds** (Node modules caching).
  * Image sync/load: **~12 seconds** per image (transfers image layers directly into Minikube container runtime).

---

## Step 3: Base Workload Deployments (Phases 2 & 3)
* **What I did**: Wrote and deployed manifests for application namespaces, configurations, deployments, and ingress routing.
* **Files created**:
  * [namespace.yaml]: Created namespace `vitals-app`.
  * [configmap.yaml]: Environment variables (`BACKEND_URL` pointing to internal DNS name, and `PORT`).
  * [secret.yaml]: Base64 encoded port (`ODA4MA==` for `8080`).
  * [backend-deployment.yaml]: 1 replica of `vitals-backend:latest` with CPU limit `200m`, memory limit `128Mi`, liveness/readiness probes at `/health`.
  * [frontend-deployment.yaml]: 2 replicas of `vitals-frontend:latest` with load balancing.
  * [services.yaml]: Inter-namespace service discovery ports.
  * [ingress.yaml]: Maps `vitals.local` to frontend.

* **Commands run**:
  ```bash
  kubectl apply -f manifests/namespace.yaml
  kubectl apply -f manifests/
  ```
* **Wait times**:
  * Pod scheduling and liveness/readiness probe validation: **~15 seconds** (Pods transition to `Running` and `1/1 READY`).

* **Verification runs**:
  * Checked pod logs: `kubectl logs -l app=vitals-backend -n vitals-app`
  * Checked internal DNS connectivity:
    ```bash
    kubectl exec -n vitals-app <frontend-pod-name> -- wget -qO- http://vitals-backend-service:8080/health
    # Output: {"status":"ok"}
    ```
  * Checked Ingress controller routing (using non-root host port forwarding):
    ```bash
    kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80 &
    curl -H "Host: vitals.local" http://localhost:8080/config
    # Output: {"backendUrl":"http://vitals-backend-service:8080","webServer":"vitals-frontend-..."}
    ```

---

## Step 4: Persistent Volume Claims (Phase 4)
* **What I did**: Configured persistent disk mappings to preserve data across container crashes and reschedules.
* **Files created**:
  * [storage.yaml]: Defined HostPath `PersistentVolume` (`jenkins-pv` at `/data/jenkins-home` on node) and `PersistentVolumeClaim` (`jenkins-pvc` requesting `5Gi`).
* **Commands run**:
  ```bash
  kubectl apply -f manifests/storage.yaml
  ```
* **Wait times**:
  * Immediate binding (**~1 second**).
* **Verification**:
  * `kubectl get pv,pvc -n vitals-app` (shows `Bound` status).

---

## Step 5: Jenkins CI/CD & RBAC (Phase 5)
* **What I did**: Deployed Jenkins with permissions restricted to the `vitals-app` namespace and validated data persistence.

* **Files created**:
  * [cicd-rbac.yaml]: ServiceAccount (`jenkins-sa`), Role, and RoleBinding.
  * [cicd-deployment.yaml]: Jenkins deployment mounting `jenkins-pvc`.
  * [Jenkinsfile.k8s]: In-cluster Kubernetes pipeline definition.

* **Troubleshooting Log**:
  * **Issue**: The initial pod crashed with `CrashLoopBackOff`.
  * **Logs checked**: `kubectl logs deployment/vitals-cicd -n vitals-app`
  * **Root Cause**: `touch: cannot touch '/var/jenkins_home/copy_reference_file.log': Permission denied`. The hostPath directory `/data/jenkins-home` inside the Minikube VM was owned by `root`, preventing the container's standard `jenkins` user (UID `1000`) from writing to it.
  * **Resolution**: Updated `cicd-deployment.yaml` to run the container as root using `runAsUser: 0` in the security context. Applied the changes, and the Pod booted successfully.

* **Commands run**:
  ```bash
  kubectl apply -f manifests/cicd-rbac.yaml -f manifests/cicd-deployment.yaml
  ```
* **Wait times**:
  * Jenkins Docker image pull: **~40 seconds**.
  * Jenkins fully initialized and up: **~12 seconds**.
* **Verification & Resilience testing**:
  * **Persistence**: Wrote a verification file `/var/jenkins_home/persistence-test.txt` inside the container. Deleted the Pod:
    ```bash
    kubectl delete pod -n vitals-app -l app=vitals-cicd
    ```
    Verified the new Pod spawned in its place still had the file intact with matching text.
  * **RBAC limitation**: Evaluated permissions from the host:
    ```bash
    kubectl auth can-i create deployment --as=system:serviceaccount:vitals-app:jenkins-sa -n vitals-app # Returns: yes
    kubectl auth can-i create deployment --as=system:serviceaccount:vitals-app:jenkins-sa -n default    # Returns: no
    ```
---

## Step 6: Observability (Phase 6)
* **What I did**: Deployed a fully integrated, resource-optimized monitoring, alerting, and logging system.
* **Files created/modified**:
  * [monitoring-values.yaml]: Capped Prometheus operator components to ~800MB RAM.
  * [prometheus-rules.yaml]: PromQL alert definitions.
  * [servicemonitor.yaml]: Application scraping target mapping.
  * [elasticsearch.yaml]: Capped at 512MB RAM with `-Xms128m -Xmx256m` JVM settings.
  * [fluent-bit.yaml]: DaemonSet parsing and forwarding metadata logs to Elasticsearch.
  * [kibana.yaml]: UI console capped at 512MB limit.
* **Commands run**:
  ```bash
  # Install Prometheus Operator
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f manifests/monitoring-values.yaml
  
  # Apply Alerts, scrapers, and Logging stack
  kubectl apply -f manifests/prometheus-rules.yaml -f manifests/servicemonitor.yaml
  kubectl apply -f manifests/elasticsearch.yaml -f manifests/fluent-bit.yaml -f manifests/kibana.yaml
  ```
* **Wait times**:
  * Helm deployment execution: **~10 seconds**.
  * Operator CRDs auditing & initializations: **~2 minutes** (Alertmanager, Prometheus operator components, and node exporter pulling and starting).
  * Elasticsearch and Kibana download & booting: **~80 seconds**.
* **Verification**:
  * Checked all namespaces: `kubectl get pods -n monitoring` and `kubectl get pods -n logging` (all pods show `Running` and ready).

---

## Step 7: Autoscaling & Vulnerability Scanning (Phase 7)
* **What I did**: Enabled the Metrics Server addon, deployed the Horizontal Pod Autoscaler (HPA) targeting `vitals-frontend` to dynamically scale based on CPU load, and integrated Trivy security scanning to the Jenkins Pipeline agent to automatically audit docker images for CVEs.
* **Files created/modified**:
  * [hpa.yaml]: Configured HPA targeting `vitals-frontend` with min replicas 2, max replicas 5, and scaling threshold at 50% CPU.
  * [Jenkinsfile.k8s]: Defined the `trivy` security scanning stage container and pipeline step.
* **Commands run**:
  ```bash
  minikube addons enable metrics-server
  kubectl apply -f manifests/hpa.yaml
  ```
* **Wait times**:
  * Metrics Server addon activation & container download: **~1 minute**.
  * Metrics aggregation lag: **~60-90 seconds** (needed for metrics-server to boot up, start querying kubelet, and expose averages so that HPA targets change from `<unknown>/50%` to resolved CPU percentages like `2%/50%`).
* **Verification**:
  * Checked HPA query resolution:
    ```bash
    kubectl get hpa -n vitals-app
    # Output:
    # NAME                  REFERENCE                    TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
    # vitals-frontend-hpa   Deployment/vitals-frontend   cpu: 2%/50%   2         5         2          2m
    ```
  * Checked image security scans inside Jenkins Pipeline pod environment using Trivy.
