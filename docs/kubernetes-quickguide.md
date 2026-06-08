# Kubernetes Mental Model Notes
This document serves as a quick reference for Kubernetes concepts and definitions.

## Core Hierarchy

```text
Cluster
 ├── Node
 │    ├── Pod
 │    │    └── Container
```

* Cluster = collection of machines working together
* Node = machine participating in Kubernetes
* Pod = wrapper around one or more containers
* Container = actual application process

---

# What is Kubernetes?

Kubernetes (k8s) is a container orchestration platform.
Responsibilities:

* scheduling containers
* scaling applications
* networking
* self-healing
* deployments

"k8s" means:
* K + 8 letters + s
---

# What is a Node?
A node is a machine in the cluster.
A node can be:

* physical server
* virtual machine (VM)
* Docker container (for local learning)

Nodes provide:

* CPU
* RAM
* storage

---
# Control Plane vs Worker Nodes
## Control Plane (Server Node)

Purpose:
* manages the cluster
* schedules workloads
* exposes Kubernetes API
* stores cluster state

Acts like:
* the "manager"

Main components:
* API server
* scheduler
* controller manager
* etcd

---

## Worker Node (Agent Node)

Purpose:
* runs applications
* hosts pods and containers

Acts like:
* the "worker"

---
# Kubernetes Distributions and Tools
## Kubernetes / k8s
The actual orchestration platform.
---
## k3s

Lightweight Kubernetes distribution.

Smaller and easier than full Kubernetes.

Still REAL Kubernetes.
---

## k3d
Tool that runs k3s inside Docker containers.
Purpose:

* local development
* fast learning
* lightweight clusters

---
## Minikube
Tool for running a local Kubernetes cluster.
Commonly used for:

* learning
* tutorials
* local projects

---
## Kind

"Kubernetes in Docker"
Mostly used for:

* testing
* CI environments

---

# Local Kubernetes with k3d
```text
Laptop
 └── Docker
      └── k3d containers
            └── k3s
                  └── Pods
                        └── App containers
```

The node itself is a Docker container pretending to be a machine.
---

# Local Kubernetes with Minikube

```text
Laptop
 └── Minikube VM/container
       └── Kubernetes
             └── Pods
                   └── Containers
```

---
# Important Kubernetes Objects
## Pod
Smallest deployable unit in Kubernetes.
Usually contains:
* one app container
---

## Deployment
Manages pods.
Provides:
* replicas
* rolling updates
* self-healing

---

## Service
Provides stable networking access to pods.
Types:
* ClusterIP
* NodePort
* LoadBalancer

---
## Ingress
HTTP/HTTPS routing into the cluster.
Example:
* frontend.example.com → frontend service

---
## ConfigMap
Stores non-sensitive configuration.
---

## Secret
Stores sensitive data:
* passwords
* API keys
* tokens

---
## Persistent Volume (PV)
Actual storage resource.
---

## Persistent Volume Claim (PVC)
Request for storage made by pods.
---

# Helm
Helm = package manager for Kubernetes.
A Helm chart bundles:
* deployments
* services
* ingress
* configs
into reusable templates.
---
# ArgoCD
GitOps deployment tool.
Purpose:
* sync Kubernetes state with Git repository
* automatically deploy changes
* detect configuration drift

---
# Monitoring Stack
## Prometheus
Collects metrics.

---
## Grafana
Visualizes metrics with dashboards.

---
# Logging Stack (EFK)
## Elasticsearch
Stores logs.

## Fluentd / Fluent Bit
Collects logs.

## Kibana
Visualizes logs.

---
