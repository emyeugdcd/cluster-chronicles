#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting Cluster Chronicles deployment..."

# 1. Start Minikube
echo "Step 1: Starting Minikube cluster..."
minikube start --driver=docker --cpus=4 --memory=6144
minikube addons enable ingress

# 2. Build and Load Docker Images
echo "Step 2: Building backend and frontend Docker images..."
docker build -t vitals-backend:latest ./backend
docker build -t vitals-frontend:latest ./frontend

echo "Loading images into Minikube container cache..."
minikube image load vitals-backend:latest
minikube image load vitals-frontend:latest

# 3. Create Namespaces and Storage
echo "Step 3: Creating namespaces and persistent storage resources..."
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/storage.yaml

# 4. Deploy Core App Workloads
echo "Step 4: Deploying core vitals backend & frontend manifests..."
kubectl apply -f manifests/configmap.yaml -f manifests/secret.yaml
kubectl apply -f manifests/backend-deployment.yaml -f manifests/frontend-deployment.yaml -f manifests/services.yaml -f manifests/ingress.yaml

# 5. Deploy Jenkins (CI/CD)
echo "Step 5: Deploying Jenkins CI/CD controller..."
kubectl apply -f manifests/cicd-rbac.yaml -f manifests/cicd-deployment.yaml

# 6. Deploy Observability Stack
echo "Step 6: Installing Prometheus Operator and Grafana via Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f manifests/monitoring-values.yaml

echo "Applying custom Prometheus metrics scrapers and alert rules..."
kubectl apply -f manifests/prometheus-rules.yaml -f manifests/servicemonitor.yaml

echo "Deploying Elasticsearch, Kibana, and Fluent Bit logs daemonset..."
kubectl apply -f manifests/elasticsearch.yaml -f manifests/fluent-bit.yaml -f manifests/kibana.yaml

# 7. Deploy HPA Autoscaling
echo "Step 7: Enabling metrics-server and HPA autoscaler..."
minikube addons enable metrics-server
kubectl apply -f manifests/hpa.yaml

echo "✅ All workloads applied successfully!"
echo "----------------------------------------------------------------"
echo "Check pods status using: kubectl get pods -A"
echo "Start port-forwards using commands inside README.md."
echo "----------------------------------------------------------------"
