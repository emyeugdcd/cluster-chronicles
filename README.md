# Cluster Chronicles: Kubernetes Workload Migration & Observability

This project continues from the previous four projects and demonstrates the complete migration of a microservices application (Go Backend + NodeJS Frontend) from traditional VM-based environments (`sherlock-logs`) to a local, Kubernetes-orchestrated cluster using **Minikube**. 

It implements persistent storage mapping, Role-Based Access Control (RBAC), and a fully optimized Observability Stack (Prometheus, Grafana, Alertmanager, Elasticsearch, Fluent Bit, and Kibana).

Here's a summary of all previous projects so you have context for what you're reviewing:

**Project 1 - Server Sorcery**: I have built a network of 4 virtual machines simulating real-life infrastructure: a load balancer, two web servers, an app server. 
- Each VM is automatically installed with the necessary software, security hardening (UFW, Fail2Ban, SSH restrictions), and networking configuration using Ansible.

Link to project 1: [https://github.com/emyeugdcd/server-sorcery-101](https://github.com/emyeugdcd/server-sorcery-101)

**Project 2 - Infrastructure Insight**: with the 4 VMs of the first project running, I then built a surgical-theatre-themed system metrics dashboard (well since I am a surgical nurse haha). The backend is a Go application running on the appserver: it reads raw performance data directly from the appserver's Linux kernel's virtual filesystem and exposes that data as a JSON API. The frontend is a Node.js application running on both webservers: it fetches from the backend API and renders the metrics as a live Medical Dashboard in the browser. When you visit http://192.168.56.11/, the loadbalancer routes your request to either webserver1 or webserver2. Backend and Frontend applications are deployed by Docker.

Link to project 2: [https://github.com/emyeugdcd/infrastructure-insight](https://github.com/emyeugdcd/infrastructure-insight)

**Project 3 - Automation Alchemy**: Automates everything from the first two projects into a single command: ./super_deploy.sh. Additionally, a GitHub Actions CI/CD pipeline is configured so that whenever we make changes to the backend and frontend application codes and push them, the corresponding running Docker containers will be destroyed and built again. That is what CI/CD means: continuous integration and continuous delivery

Link to project 3: [https://github.com/emyeugdcd/automation-alchemy](https://github.com/emyeugdcd/automation-alchemy)

**Project 4 - Sherlock Logs**: This project builds upon the `automation-alchemy` infrastructure, integrating a robust observability stack. It adds a centralized **Monitoring VM** that hosts Prometheus, Grafana, and the ELK Stack (Elasticsearch, Logstash, Kibana) to provide real-time metrics and aggregated logging across all nodes.

Link to project 4: [https://github.com/emyeugdcd/sherlock-logs](https://github.com/emyeugdcd/sherlock-logs)


**Project 5 - Cluster Chronicles**: This project continues from the previous four projects and demonstrates the complete migration of a microservices application (Go Backend + NodeJS Frontend) from traditional VM-based environments (`sherlock-logs`) to a local, Kubernetes-orchestrated cluster using **Minikube**. 


---

## 1. Prerequisites & Cross-Platform Installation

Before starting, ensure the following core tools are installed on your host machine based on your Operating System:

### A. macOS Setup (Intel / Apple Silicon)
1. Install **Docker Desktop**: [Download Link](https://www.docker.com/products/docker-desktop/) (Enable "Use Virtualization framework" under settings).
2. Install tools via Homebrew:
   ```bash
   brew install minikube kubectl helm k9s
   ```

### B. Windows Setup (WSL 2)
1. Install **Docker Desktop for Windows** and enable the **WSL 2 backend** in settings.
2. Open your WSL 2 terminal (e.g. Ubuntu) and install dependencies:
   ```bash
   # Install kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # Install Minikube
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   
   # Install Helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

### C. Linux Setup (Ubuntu/Debian)
1. Install Docker Engine: `sudo apt install docker.io -y` (Add user: `sudo usermod -aG docker $USER && newgrp docker`).
2. Install Minikube and Kubectl using the Debian package managers or standard curl releases.

---

## 2. Step-by-Step Cluster Setup Playbook

Execute the following commands in order to bring up the entire environment:

### Step 1: Start Minikube & Enable Addons
Start the cluster with 4 CPUs and 6GB RAM (optimized threshold):
```bash
minikube start --driver=docker --cpus=4 --memory=6144
minikube addons enable ingress
```

### Step 2: Build and Sync Local Images
Build the application containers on your host machine and load them directly into Minikube's internal container cache:
```bash
# Build backend (Go)
docker build -t vitals-backend:latest ./backend

# Build frontend (NodeJS)
docker build -t vitals-frontend:latest ./frontend

# Load into Minikube
minikube image load vitals-backend:latest
minikube image load vitals-frontend:latest
```

### Step 3: Deploy Core Applications & Storage
Create the namespace, mount persistent volumes, configure RBAC, and apply deployments:
```bash
# Create namespaces and storage
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/storage.yaml

# Apply core deployments, services, configs, and ingress routing
kubectl apply -f manifests/configmap.yaml -f manifests/secret.yaml
kubectl apply -f manifests/backend-deployment.yaml -f manifests/frontend-deployment.yaml -f manifests/services.yaml -f manifests/ingress.yaml
```

### Step 4: Deploy Jenkins (CI/CD)
Apply the ServiceAccount permission structure and spawn Jenkins:
```bash
kubectl apply -f manifests/cicd-rbac.yaml -f manifests/cicd-deployment.yaml
```

### Step 5: Deploy the Observability Stack 
Add the Prometheus Helm chart, apply custom alerting rules, and deploy the EFK logging stack:
```bash
# Deploy Prometheus Operator & Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f manifests/monitoring-values.yaml

# Apply ServiceScrapers and Rules
kubectl apply -f manifests/prometheus-rules.yaml -f manifests/servicemonitor.yaml

# Apply Logging stack (Elasticsearch, Fluent Bit, Kibana)
kubectl apply -f manifests/elasticsearch.yaml -f manifests/fluent-bit.yaml -f manifests/kibana.yaml
```

### Step 6: Deploy Autoscaling & Security Scanning 
Enable the Metrics Server, deploy the Horizontal Pod Autoscaler (HPA) for the frontend service, and inspect HPA status:
```bash
# Enable Metrics Server addon in Minikube
minikube addons enable metrics-server

# Apply the Horizontal Pod Autoscaler configuration
kubectl apply -f manifests/hpa.yaml

# Verify HPA deployment and targets
kubectl get hpa -n vitals-app
```

---

## 3. Service Access Mappings (Port-Forwards)

All core interfaces run cluster-internally. To access them on your host Mac/PC browser, run these commands in separate terminal shells:

| Component | In-Cluster Port | Host Map Address | Launch Command |
| :--- | :--- | :--- | :--- |
| **Vitals Web App** | Ingress Port 80 | [http://vitals.local:8080](http://vitals.local:8080) | `kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80` *(See note below)* |
| **Jenkins UI** | 8080 | [http://localhost:9090](http://localhost:9090) | `kubectl port-forward -n vitals-app service/vitals-cicd-service 9090:8080` |
| **Grafana UI** | 80 | [http://localhost:9000](http://localhost:9000) | `kubectl port-forward -n monitoring service/prometheus-grafana 9000:80` *(Pass: see below)* |
| **Kibana Logs** | 5601 | [http://localhost:5601](http://localhost:5601) | `kubectl port-forward -n logging service/kibana-service 5601:5601` |
| **Prometheus UI** | 9090 | [http://localhost:9191](http://localhost:9191) | `kubectl port-forward -n monitoring service/prometheus-kube-prometheus-prometheus 9191:9090` |

Or just run this one command:
### Start all port-forwards in the background
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80 &
kubectl port-forward -n vitals-app service/vitals-cicd-service 9090:8080 &
kubectl port-forward -n monitoring service/prometheus-grafana 9000:80 &
kubectl port-forward -n logging service/kibana-service 5601:5601 &
kubectl port-forward -n monitoring service/prometheus-kube-prometheus-prometheus 9191:9090 &

Note: After running these, press Enter to get your command prompt back. The services will continue running silently.

### Host Header mapping for Ingress (`vitals.local` & `vitals-backend-service`)
Add this line to your host's `/etc/hosts` file (located at `C:\Windows\System32\drivers\etc\hosts` on Windows, or `/etc/hosts` on macOS/Linux):
```text
127.0.0.1 vitals.local vitals-backend-service
```
### Grafana Login Password
Retrieve the autogenerated admin password using:
```bash
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```
*(Default username is `admin`).*



---

## 4. Running Validation & Verification Tests
Ensure you have run the following verification checks:

1. **Verify Pod Status**: `kubectl get pods -A` (All pods in namespaces `vitals-app`, `logging`, and `monitoring` should be `Running`).
2. **Verify PV Binding**: `kubectl get pv,pvc -n vitals-app` (Should show `Bound` status).
3. **Verify App logs**: `kubectl logs -l app=vitals-backend -n vitals-app`
4. **Test Internal communication**:
   ```bash
   kubectl exec -n vitals-app $(kubectl get pods -n vitals-app -l app=vitals-frontend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://vitals-backend-service:8080/health
   # Returns: {"status":"ok"}
   ```
5. **Verify Jenkins RBAC permissions**:
   ```bash
   kubectl auth can-i create deployment --as=system:serviceaccount:vitals-app:jenkins-sa -n vitals-app
   # Returns: yes
   ```
6. **Verify HPA metrics collection**:
   ```bash
   kubectl get hpa -n vitals-app
   # Target CPU utilization should resolve from <unknown>/50% to an active percentage (e.g., 2%/50%).
   ```
7. **Run Container Vulnerability Scan manually via Trivy**:
   ```bash
   # Run a test scan on the backend image
   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL vitals-backend:latest
   ```

### 5. Visualization of the Kubernetes Cluster
Minikube Cluster
 ├── Namespace: "vitals-app"
 │    ├── [ Permanent Pods ]
 │    │    ├── Pod A (vitals-backend) ──► Go App
 │    │    ├── Pod B (vitals-frontend-1) ──► Frontend Web Server
 │    │    ├── Pod C (vitals-frontend-2) ──► Frontend Web Server
 │    │    │
 │    │    └── Pod D (vitals-cicd) ──► Jenkins Controller (Always running, mounts PVC)
 │    │
 │    └── [ Temporary Pods (Only exist during a build!) ]
 │         └── Pod E (jenkins-agent) ───► Container 1: kaniko (Builds image)
 │                                   ───► Container 2: trivy (Vulnerability scan)
 │                                   ───► Container 3: kubectl (Deploys YAMLs)
 │
 └── Namespace: "ingress-nginx"
      └── Pod F (nginx-ingress-controller) ──► Routing gate


### 6. Quick UI Setup & Testing Guide (Browser Tools)
Once your port-forwards are active, here is how to verify and explore each UI:

##### Grafana (Dashboards)
Access URL: http://localhost:9000
Login Credentials:
Username: admin
Password: Retrieve it by running:
```
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

What to test:
- Click the Menu icon (top-left) -> Dashboards.
- The pre-installed dashboards (imported via ConfigMaps/Helm sidecar) will be listed:
  - Kubernetes / Compute Resources / Namespace (Pods): Select namespace vitals-app to see live frontend/backend CPU and Memory consumption.
  - Vitals App Custom Dashboard: Displays your custom Go metrics (app_cpu_usage_percent, app_memory_used_mb).

##### Kibana (Centralized Logs)
Access URL: http://localhost:5601
First-Time Setup (Create Index Pattern):
- Go to Management (gear icon on the left sidebar) -> Stack Management.
- Click Index Patterns -> Create index pattern.
- Under Name, type * to see everything, then click Next step.
- Select @timestamp as the Primary Time Field and click Create index pattern.
What to test:
- Go to Analytics -> Discover (compass icon).
You will see a live stream of aggregated logs from all nodes.
Search vitals-backend or vitals-frontend in the search bar to filter logs instantly.

##### Prometheus (Metrics & Alert Rules)
Access URL: http://localhost:9191
What to test:
- Querying metrics: In the home search box, type app_cpu_usage_percent or kube_pod_container_status_restarts_total and click Execute. Click the Graph tab to see metrics plotting over time.
- Monitoring alerts: Click the Alerts tab in the top navigation bar. You will see all our configured alert rules from prometheus-rules.yaml (e.g. NodeCPUUsageHigh, PodStuckInPending). They will be colored:
  - Green (Inactive): Condition not met (all good).
  - Yellow (Pending): Condition met, but waiting for the for duration limit (e.g. CPU > 80% for less than 5 minutes).
  - Red (Firing): Condition met and threshold exceeded the duration limit. An alert message has been generated and sent to Alertmanager!

### 7. Cleaning up
How to clean up Kubernetes cache and cluster state on your machine?
Kubernetes resources (deployments, pods, services) don't save physical files to your host machine disk (they live inside Minikube's virtual machine/container). However, if we keep rebuild/delete cycles active, Docker images and persistent volumes can consume disk space over time.

Here are the cleanup commands:

To destroy the entire cluster: This deletes the Minikube node VM/containers, removing all cluster configurations, cached databases, and persistent volumes:
```
minikube delete
```

To clean up Docker images and build caches on your machine: If you build images locally with docker build, build caches and untagged images accumulate. Run this to reclaim space:
```
docker system prune -a --volumes --force
```

To clean up unused images inside Minikube: If you loaded many test images into Minikube, clean them up inside the cluster runtime:
```
minikube image prune
```

### 8. Docs
In this project, I have created several documents to help understand the project better. You can find them in the `docs` folder. Some of the key documents are:
- autoscaling-security.md, k9s-lens-tutorial.md, kubernetes-quickguide.md, learning-notes.md, manifests-guide.md, proxy.md, walkthrough.md: These documents serve to provide a comprehensive understanding of the project, with new concepts, definitions and guides, from the basics of Kubernetes to the advanced concepts of autoscaling and security.
- project-overview.md: requirements of the project
- testing-requirements.md: testing requirements by kood/sisu and answers for the test in markdown format (also, for some tests: guidances on how to test for them)