#  Autoscaling & Vulnerability Scanning

This guide explains the autoscaling mechanism and the security audit layer that was implemented in this Kubernetes cluster project.

---

## 1. The Metrics Server & Horizontal Pod Autoscaler (HPA)

### What is the Metrics Server?
By default, Kubernetes has no idea how much CPU or Memory a container is actively consuming. It only knows what we *requested* (in our Deployment specs). 
The **Metrics Server** is a cluster-wide aggregator of resource usage data.
* It queries the kubelet (the node agent) on every node.
* It collects CPU and Memory metrics from all running Pods and Nodes.
* It exposes these metrics to the Kubernetes API, making them readable by commands like `kubectl top` and controllers like the **HPA**.

### What is the Horizontal Pod Autoscaler (HPA)?
The **HPA** (`kind: HorizontalPodAutoscaler`) is a controller that automatically adjusts the number of replicas in a deployment based on live resource consumption.

In our project, we deployed `hpa.yaml` targeting the frontend:
* **Minimum replicas:** 2
* **Maximum replicas:** 5
* **Metric target:** 50% CPU utilization.

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vitals-frontend
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 50
```

### How HPA and Metrics Server fit together:
```text
  ┌──────────────────────────────────────────────────────────┐
  │                     Minikube Cluster                     │
  │                                                          │
  │  ┌──────────────┐             CPU/RAM Stats              │
  │  │ Frontend Pod │──────────────────────────────────┐     │
  │  └──────────────┘                                  │     │
  │                                                    ▼     │
  │  ┌──────────────┐   Queries metrics     ┌────────────────┐│
  │  │   HPA Loop   │◄──────────────────────│ Metrics Server ││
  │  └──────┬───────┘   every 15s           └────────────────┘│
  │         │                                                │
  │         │ (If average CPU > 50%, scale up)               │
  │         ▼                                                │
  │  ┌──────────────┐                                        │
  │  │  Deployment  │──► scales replicas from 2 to 3, 4, etc.│
  │  └──────────────┘                                        │
  └──────────────────────────────────────────────────────────┘
```
---

## 2. Vulnerability Scanning with Trivy

### What is Trivy?
**Trivy** (by Aqua Security) is a lightweight, fast scanner for vulnerabilities in container images, file systems, Git repositories, and Kubernetes configurations.
* It downloads a database of known security vulnerabilities (CVEs - Common Vulnerabilities and Exposures).
* It scans the package managers, libraries, and OS files inside your Docker image (e.g., `vitals-backend:latest`).
* It reports if there are critical security holes that hackers could exploit.

### How Trivy fits into our Pipeline:
In `Jenkinsfile.k8s`, we added a security gate using Trivy:
1. **Build:** We build the Docker container image.
2. **Scan:** Before deploying, our Jenkins agent starts a temporary container running `trivy`. It scans our image.
3. **Block:** We can configure Trivy to fail the build (e.g., `--exit-code 1`) if it finds `HIGH` or `CRITICAL` severity vulnerabilities. This prevents compromised images from ever making it to our cluster!

```groovy
stage('Security Scan (Trivy)') {
    steps {
        container('trivy') {
            echo "Scanning Docker image for vulnerabilities..."
            sh 'trivy image --severity HIGH,CRITICAL vitals-backend:latest'
        }
    }
}
```
