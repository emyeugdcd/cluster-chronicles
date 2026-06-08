# Kubernetes Migration To-Do List (Cluster Chronicles)
So when I started this project, I feel like I need to have a to-do list of what I need to do, step by step, so I can track my progress and actually study and grasp the concept gradually. I don't want to be overwhelmed and confused by the new concepts and tools.

Hence, this is the step-by-step checklist to migrate from Vagrant VMs to a local Kubernetes cluster based on the project requirements. This document is meant to read side-by-side with walkthrough.md, which has the detailed walkthrough of each step.

## Phase 1: Kubernetes Environment Setup
- [x] Install `minikube` on local machine.
- [x] Install `kubectl` command-line tool.
- [x] Start local Minikube cluster (`minikube start`).
- [x] *(Optional but recommended)* Install a Kubernetes IDE like Lens or K9s to visualize the cluster.

## Phase 2: Application Containerization & Manifests 
*Note: In Kubernetes, we don't install software via `apt` on VMs. Instead, we write YAML files that tell Kubernetes how to run our Docker containers.*
- [x] **Backend Deployment:** Write a `backend-deployment.yaml` for a single backend replica, including resource requests/limits.
- [x] **Frontend Deployment:** Write a `frontend-deployment.yaml` for two frontend replicas, including resource requests/limits.
- [x] **Services:** Write a `services.yaml` defining internal networking for the backend and frontend.
- [x] **ConfigMaps & Secrets:** Move your environment variables (like `BACKEND_URL`) into a Kubernetes `ConfigMap` or `Secret`.

## Phase 3: Deploying and Networking 
- [x] Apply all application manifests using `kubectl apply -f .`
- [x] Verify pod status and check logs to ensure they are running properly.
- [x] Verify internal communication between frontend and backend pods.
- [x] Set up an **Ingress** resource to allow local host machine's browser to access the frontend service from outside the cluster.

## Phase 4: Persistent Storage Implementation 
- [x] Define and apply `PersistentVolume` (PV) YAML files.
- [x] Define and apply `PersistentVolumeClaim` (PVC) YAML files so pods can request the storage.
- [x] Verify the PVCs successfully bind to the PVs.

## Phase 5: CI/CD Pipeline Migration 
- [x] Choose a CI/CD tool to run *inside* the cluster (e.g., Jenkins, GitLab CI).
- [x] Deploy the CI/CD tool to Kubernetes using manifests or Helm charts.
- [x] Attach Persistent Storage (PVC) to the CI/CD tool so build history isn't lost if the pod restarts.
- [x] Configure **RBAC** (Role-Based Access Control): Create a `ServiceAccount`, `Role`, and `RoleBinding` so the CI/CD tool has permission to deploy things into the cluster.
- [x] Re-write the CI/CD pipeline to deploy new Docker images to Kubernetes.

## Phase 6: The Observability Stack (Monitoring & Logging)
### Monitoring (Prometheus + Grafana)
- [x] Deploy Prometheus to the cluster.
- [x] Deploy Grafana to the cluster.
- [x] Configure Prometheus to scrape metrics from cluster nodes, pods, and application.
- [x] Import or create dashboards in Grafana for Cluster Performance, Pod Performance, and Application Performance.

### Logging (EFK Stack)
- [x] Deploy **Elasticsearch** (Notes to self: Make sure to give it enough RAM limits and attach persistent storage!).
- [x] Deploy **Fluentd or Fluent Bit** as a DaemonSet to automatically collect logs from all containers.
- [x] Deploy **Kibana** to visualize the logs. (Notes to self: It can take a while to start, just be patient and check the logs).
- [x] Create dashboards in Kibana to search application and system logs.

### Alerting (Prometheus Alertmanager)
- [x] Configure Node Alerts: High CPU (>80% for 5m), High Memory (>90% for 5m), Low Disk (<20%).
- [x] Configure Pod Alerts: CrashLoopBackOff (>3 restarts in 15m), High Memory (>80% of limit), Pending state (>5m).
- [x] Configure Cluster Alerts: Kubernetes API unreachable.
- [x] Configure Logging Alerts: Elasticsearch health goes yellow/red, Fluentd log collection errors.

## Phase 7: Extra Challenges 
- [x] **Security:** Integrate a vulnerability scanner (like Trivy) into CI/CD pipeline to scan images before deploying them.
- [x] **Autoscaling:** Implement an `HorizontalPodAutoscaler` (HPA) for the frontend so it automatically scales up replicas when CPU utilization spikes.
