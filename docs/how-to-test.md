# Cluster Chronicles: Rubric Testing & Requirements Validation

This document contains the verified theoretical answers, file references, and testing procedures for the **Cluster Chronicles** Kubernetes migration project. Each section corresponds to a specific rubric requirement, mapping the concept directly to the active configuration files and verification commands.

---

## Part 1: Kubernetes Architecture & Concepts

### 1. Student demonstrates understanding of key Kubernetes architecture components
* **API Server (`kube-apiserver`)**: The entry point for all cluster administration. It exposes the Kubernetes REST API, validates and processes manifests, and updates the cluster state in `etcd`.
* **etcd**: A highly available, distributed key-value store acting as the cluster's single source of truth for all configuration and state data.
* **Controller Manager (`kube-controller-manager`)**: Runs background daemon controllers (such as the Node, ReplicaSet, and Deployment controllers) that continuously watch the state of the cluster via the API Server and attempt to reconcile the current state with the desired state.
* **Scheduler (`kube-scheduler`)**: Watches for newly created Pods that have no assigned node, evaluates resource constraints, affinity/anti-affinity, taints/tolerations, and schedules them onto the optimal node.
* **Kubelet**: The node agent running on every worker node. It registers the node, receives PodSpecs from the API Server, ensures that the described containers are running and healthy, and reports status back to the control plane.

### 2. Student can articulate the benefits and drawbacks of using Kubernetes over traditional VM-based deployments
* **Benefits**:
  * **Density & Resource Efficiency**: Containers share the host OS kernel, allowing hundreds of microservices to run efficiently on a shared pool of nodes with minimal overhead compared to heavy VMs.
  * **Self-Healing**: Automatic restarts, replication, and rescheduling of crashed or unresponsive pods.
  * **Declarative Configuration & GitOps**: Infrastructure-as-code manifests can be stored in Git, enabling version control, audit trails, and automatic drift reconciliation.
  * **High Portability**: Consistently runs workloads across developer laptops (e.g., Minikube), on-premise servers, or public clouds (AWS, GCP).
* **Drawbacks**:
  * **High Complexity**: Significant learning curve; routing, persistent storage, and multi-tenant networking require advanced expertise to troubleshoot.
  * **Operational Overhead**: Requires base control-plane components (API server, etcd, etc.) and cluster agents, which consume resources even when idle.

### 3. Student can explain the purpose and benefits of using namespaces in Kubernetes
* **Purpose**: Namespaces logically partition a single physical Kubernetes cluster into virtual sub-clusters.
* **Benefits**:
  * **Name Collision Prevention**: Allows identical resource names (e.g., `vitals-backend`) to coexist in different stages (e.g., development, staging, production) within the same cluster.
  * **Access Control & Security**: Serves as a scope for Role-Based Access Control (RBAC) and NetworkPolicies, isolating developer groups and workloads.
  * **Resource Quotas**: Enables administrators to set CPU and memory limits per namespace to prevent resource starvation.

### 4. Student can explain the difference between a Deployment and a StatefulSet in Kubernetes and when to use one over the other
* **Deployment**:
  * **Behavior**: Manages stateless applications. Pods are interchangeable and get random, dynamic hostnames (e.g., `vitals-frontend-a1b2c`). Volumes are detached and attached dynamically without matching specific pod identities.
  * **When to use**: Web frontends, stateless REST APIs, and microservices where any instance can handle any incoming request.
* **StatefulSet**:
  * **Behavior**: Manages stateful workloads. Pods get stable, unique, ordinal network identifiers (e.g., `db-0`, `db-1`, `db-2`) that persist across restarts. They bind to persistent volumes using a volume claim template, ensuring a specific pod index always reconnects to its designated volume.
  * **When to use**: Databases (PostgreSQL, MySQL), message brokers (Kafka, RabbitMQ), and distributed storage systems where node identity and order matter.

### 5. Student can describe the Kubernetes networking model and how pods communicate with each other across nodes
* **Networking Model**: 
  * Every Pod in a cluster is assigned a unique, routable IP address. 
  * Pods can communicate with all other pods on any node without using Network Address Translation (NAT).
* **Cross-Node Communication**:
  * Managed by a **Container Network Interface (CNI)** plugin (e.g., Calico, Cilium, or Minikube's built-in bridge).
  * The CNI establishes an overlay network (using encapsulation protocols like VXLAN or Geneve) or routes packets directly. When a pod on Node A sends a packet to a pod on Node B, the CNI encapsulates the packet, routes it across the host network, and decapsulates it on Node B, delivering it directly to the target pod interface.

### 6. Student can explain the purpose of the kube-proxy component in Kubernetes and how it facilitates service load balancing
* **Purpose**: `kube-proxy` is a network agent running on each cluster node that maintains network rules on the host to map virtual Service IPs to healthy backing Pod IPs.
* **Service Load Balancing**:
  * It monitors the API Server for the creation or modification of `Services` and `Endpoints`.
  * It configures IP tables (or IPVS rules) on the host machine.
  * When a container sends a request to a Service IP (e.g., `vitals-backend-service`), the host's iptables rules intercept the packet and translate the destination IP (DNAT) to one of the matching pod IPs, distributing traffic evenly.

### 7. Student can explain the concept of Kubernetes Operators and how they extend Kubernetes functionality
* **Concept**: An Operator combines **Custom Resource Definitions (CRDs)** and custom controller loops to package human operational knowledge into software code.
* **How it extends functionality**:
  * CRDs define new API endpoints (e.g., `PrometheusRule` or `ServiceMonitor`).
  * The Operator's controller continuously polls the API Server for these custom objects and automatically handles complex, stateful operations (like upgrading databases, running backups, or dynamically updates scraping targets) without manual human intervention.
  * **Example**: The Prometheus Operator listens for `ServiceMonitor` resources and automatically reconfigures Prometheus's scrape targets.

### 8. Student can explain the limitations of Minikube compared to a production Kubernetes cluster and identify features that are not available or behave differently
* **Single-Node Limitation**: Minikube typically runs on a single node (inside a VM or Docker container). Multi-node failover, pod rescheduling due to node failure, and inter-node scheduling constraints (like node anti-affinity) cannot be realistically tested.
* **HostPath Storage**: Minikube uses `hostPath` storage, mapping files directly to the single node's filesystem. Production clusters use high-availability network storage (AWS EBS, GCP Persistent Disks, Ceph).
* **LoadBalancer Support**: Minikube cannot provision real external cloud load balancers. Accessing services of type `LoadBalancer` requires running `minikube tunnel` to map the service port to the host's localhost port.

### 9. Student can explain the use of Kubernetes probes (readiness, liveness, startup) in deployment manifests
* **Startup Probe**: Determines if the application inside the container has successfully booted. All other probes (liveness, readiness) are disabled until the startup probe succeeds, preventing slow-starting apps from being terminated early.
* **Liveness Probe**: Determines if the container needs to be restarted. If the liveness check fails, the Kubelet kills the container and triggers its restart policy.
* **Readiness Probe**: Determines if the container is ready to accept incoming network traffic. If it fails, the pod's IP is removed from the Endpoints list of all matching Services.

> [!NOTE]
> In our project, the application containers boot instantly. Therefore, [backend-deployment.yaml] and [frontend-deployment.yaml] implement `livenessProbe` and `readinessProbe` targeting the HTTP `/health` and `/` endpoints respectively.

### 10. Student can explain how to implement resource requests and limits for pods and describe what happens if a pod exceeds its memory limit
* **Implementation**: Defined in the container specification of a deployment manifest:
  * **Requests**: The minimum amount of CPU and memory the scheduler guarantees to allocate for the container.
  * **Limits**: The absolute maximum cap on CPU and memory the container is allowed to consume.
* **Exceeding Memory Limits**:
  * Memory is a non-compressible resource. If a container exceeds its memory limit, the Linux kernel out-of-memory (OOM) killer terminates the primary process, and the pod is restarted with status `OOMKilled`.

### 11. Student can explain the purpose of init containers in a pod and provide an example where init containers solve a deployment problem
* **Purpose**: Init containers run *before* the application containers start, executing sequentially to completion. If an init container fails, the Pod restarts until it succeeds.
* **Example Use Case**: A backend application needs a database to be fully initialized and reachable before booting. An init container running a simple wait loop (e.g., executing `pg_isready` or checking port connectivity via `nc`) prevents the backend application container from crash-looping while the database starts up.

---

## Part 2: Practical Workloads, Networking & Storage

### 12. Kubernetes manifests are created for backend and frontend deployments
* The manifests are located in the [manifests] directory:
  * [backend-deployment.yaml]: Deploys the Go-based API backend.
  * [frontend-deployment.yaml]: Deploys the Node.js-based web frontend.

### 13. Application manifests are successfully applied and deployed
* Manifests are applied using the command:
  ```bash
  kubectl apply -f manifests/namespace.yaml
  kubectl apply -f manifests/
  ```

### 14. Upon startup, backend has 1 replica and frontend 2 replicas
* Specified in the deployment manifests and verified using:
  ```bash
  kubectl get deployments -n vitals-app
  ```
  * `vitals-backend` runs with `replicas: 1`.
  * `vitals-frontend` runs with `replicas: 2`.

### 15. Services and Ingress are configured. Ensure that the services enable internal communication and the ingress allows external access.
* **Services**: Defined in [services.yaml]. It exposes:
  * `vitals-backend-service` (ClusterIP, port 8080) for secure internal pod-to-pod communication.
  * `vitals-frontend-service` (ClusterIP, port 3000) for frontend access.
* **Ingress**: Defined in [ingress.yaml]. It configures the Nginx Ingress Controller to route traffic targeting host `vitals.local` directly to the `vitals-frontend-service` on port 3000.

### 16. Student can troubleshoot deployment issues. Use of kubectl commands to diagnose and fix issues.
* **Key Commands**:
  * Get resource status: `kubectl get pods,svc,deploy -n vitals-app`
  * Fetch logs: `kubectl logs <pod-name> -n vitals-app`
  * Inspect configuration and lifecycle events: `kubectl describe pod <pod-name> -n vitals-app`
  * Check ingress logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`

### 17. Student can explain how to configure network policies to restrict pod-to-pod communication and address security considerations
* **Concept**: By default, all pods in a cluster can communicate freely. **NetworkPolicies** act as pod-level firewalls. CNI plugins (like Calico) enforce these rules at the network layer.
* **Implementation Example**:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: backend-policy
    namespace: vitals-app
  spec:
    podSelector:
      matchLabels:
        app: vitals-backend
    policyTypes:
    - Ingress
    ingress:
    - from:
      - podSelector:
          matchLabels:
            app: vitals-frontend
      ports:
      - protocol: TCP
        port: 8080
  ```
  * This policy blocks all traffic to the backend pods except for ingress connections coming directly from pods labeled `app: vitals-frontend` on port 8080.

### 18. Student can explain the difference between ClusterIP, NodePort, and LoadBalancer service types and justify the choice of specific service types for components
* **ClusterIP**: Exposes the service on a cluster-internal IP. Backing pods are only reachable from within the cluster.
  * *Choice*: Used for `vitals-backend-service` to protect the database and business logic from external exposure.
* **NodePort**: Exposes the service on each node's IP at a static port (in the range 30000-32767).
  * *Choice*: Useful for testing or exposing internal admin consoles (like Jenkins) in local environments without setting up DNS names.
* **LoadBalancer**: Provisions a cloud provider's external load balancer (e.g., AWS NLB/ALB) that routes traffic to NodePorts automatically.
  * *Choice*: Used for production ingress controllers to expose the application to the internet.

### 19. Student can explain the importance of persistent storage in Kubernetes
* **Importance**: Containers are ephemeral; any data written to the container's local filesystem is destroyed if the container crashes or is rescheduled. Persistent volumes decouple storage lifecycle from the pod lifecycle, ensuring databases, stateful configurations, and build logs persist across pod replacements.

### 20. Persistent Volumes (PVs) and Persistent Volume Claims (PVCs) are defined
* Deployed via [storage.yaml].
  * **PV**: `jenkins-pv` allocates 5Gi of local node path (`/data/jenkins-home`).
  * **PVC**: `jenkins-pvc` requests 5Gi of storage using the `manual` storage class to bind to the PV.

### 21. Student can explain the difference between ReadWriteOnce, ReadOnlyMany, and ReadWriteMany access modes for PersistentVolumes and justify the choice of access modes used
* **ReadWriteOnce (RWO)**: The volume can be mounted as read-write by a single node.
  * *Choice*: Used for the Jenkins data volume (`jenkins-pv`) since Jenkins is a single-replica stateful container and requires exclusive write access to prevent file locking issues.
* **ReadOnlyMany (ROX)**: The volume can be mounted as read-only by many nodes simultaneously.
  * *Choice*: Ideal for shared configuration directories or static asset hostings.
* **ReadWriteMany (RWX)**: The volume can be mounted as read-write by many nodes concurrently (requires network file systems like NFS or GlusterFS).
  * *Choice*: Ideal for shared uploads directories in distributed web applications.

### 22. Student can explain how to handle potential data loss scenarios when pods with persistent storage are rescheduled to different nodes
* **Scenario**: Local `hostPath` storage binds data to a specific physical node. If a pod is rescheduled to a different host node, it will mount an empty directory on the new host, leading to apparent data loss.
* **Solution**: In production, utilize **Network Attached Storage (SAN/NAS)** (such as AWS EBS, GCP Persistent Disks, or NFS). These storage engines support dynamic mounting and will detach from the old node and re-attach to the new node when the pod is rescheduled. For local storage, node affinity can be declared on the PV to force the scheduler to place the pod on the correct node.

---

## Part 3: CI/CD Pipeline & Securing Secrets

### 23. CI/CD tool is deployed on the Kubernetes cluster
* Jenkins is deployed as a single replica in the `vitals-app` namespace via [cicd-deployment.yaml]. It mounts the persistent storage via `jenkins-pvc`.

### 24. Student can articulate their choice of chosen CI/CD tool
* **Choice**: **Jenkins** was selected because it runs completely self-contained within our local cluster. Through the Kubernetes Jenkins plugin, it spins up ephemeral container-based build agents (pods) for each pipeline execution and cleans them up automatically, keeping the cluster resource footprint low.
* **Tradeoffs**:
  * **vs. GitHub Actions**: GitHub Actions is easier to manage but requires internet connectivity and external tunneling/runners to interact with a local private Minikube cluster.
  * **vs. ArgoCD**: ArgoCD is excellent for GitOps CD, but does not compile or build Docker images. Jenkins provides a unified CI/CD platform handling compile, build, vulnerability scan, and deployment in a single file.

### 25. CI/CD tool is configured to interact with the Kubernetes cluster
* Configured using [cicd-rbac.yaml].
  * Defines a ServiceAccount `jenkins-sa` bound to a specific Role `jenkins-role` within the `vitals-app` namespace. This role limits Jenkins' permissions to resources such as deployments, pods, services, configmaps, and secrets within the `vitals-app` namespace.

### 26. Student can demonstrate how to secure secrets used in the CI/CD pipeline and explain the management and rotation of these secrets
* **Best Practices**:
  * Avoid storing plaintext secrets in git repositories.
  * Inject credentials into Jenkins build pods dynamically using Kubernetes Secrets.
  * **Secret Rotation**: Update secrets using `kubectl apply` or automated tools. Applications should read configurations from mounted volumes that dynamically update, or leverage rotation triggers to roll out pods when secrets change.
  * **Production Hardening**: Integrate secret managers (HashiCorp Vault, AWS Secrets Manager) to retrieve credentials directly into memory at runtime without writing secrets to files or etcd plain text.

### 27. Student can explain how to implement rolling updates in deployment strategy and handle failed deployments and rollbacks
* **Rolling Update**: The default update strategy in Kubernetes. It replaces old pods with new pods one-by-one, ensuring zero downtime. Configured using `maxUnavailable` and `maxSurge`.
* **Failed Deployments**: If a new version fails liveness/readiness probes, Kubernetes halts the rollout, keeping the existing healthy pods running.
* **Commands**:
  * Check update status:
    ```bash
    kubectl rollout status deployment/vitals-backend -n vitals-app
    ```
  * Roll back to previous version:
    ```bash
    kubectl rollout undo deployment/vitals-backend -n vitals-app
    ```

---

## Part 4: Observability, Logging & Alerting

### 28. Prometheus is deployed and configured to scrape metrics
* Deployed using the `kube-prometheus-stack` Helm chart. It deploys the Prometheus Operator, Prometheus, Alertmanager, and Grafana in the `monitoring` namespace, optimized for low memory usage using [monitoring-values.yaml].

### 29. Student can demonstrate how to implement custom metrics in the application and ensure these are scraped by Prometheus
* **Implementation**: The Go backend [main.go] defines two custom gauges: `app_cpu_usage_percent` and `app_memory_used_mb`, and exposes them using the Prometheus client library on the `/prometheus` endpoint.
* **Scraping**: The [servicemonitor.yaml] matches the backend service labels, directing Prometheus to scrape `/prometheus` every 15 seconds.

### 30. Student can show how to configure Prometheus to use service discovery for scraping metrics and address challenges in ensuring all necessary targets are discovered
* **Service Discovery**: Prometheus Operator discovers targets dynamically by matching labels defined in `ServiceMonitor` and `PodMonitor` resources with those on Services and Pods.
* **Challenges**:
  * **Label Mismatching**: If labels on the `Service` do not match the `ServiceMonitor` selectors, the endpoint will not be discovered.
  * **Namespace Boundaries**: By default, Prometheus may not look at all namespaces unless configured with cross-namespace role bindings or broad namespace selectors.

### 31. Grafana Dashboards are configured
* Displays the metrics gathered by Prometheus.
  * **Cluster Performance**: Monitors node-level metrics (CPU, RAM, disk).
  * **Pod and Container**: Tracks individual pod resource usage against limits.
  * **Application Performance**: Visualizes backend-specific custom gauges (`app_cpu_usage_percent`, `app_memory_used_mb`).

### 32. EFK stack is deployed and Fluentd/Fluent Bit is configured to collect logs
* **Elasticsearch**: Deployed in the `logging` namespace using [elasticsearch.yaml].
* **Fluent Bit**: Deployed as a DaemonSet using [fluent-bit.yaml]. It runs on every node, collects container stdout logs, parses them, and forwards them to Elasticsearch.

### 33. Student can explain how to set up log rotation and retention policies in the EFK stack and manage log storage to prevent disk space issues
* **Log Rotation**: Handled at the node level by the container runtime (Docker/containerd), which limits log file sizes (e.g., 10MB per file, rotating after 5 files).
* **Retention Policy**: Elasticsearch implements Index Lifecycle Management (ILM) policies to automatically transition indices from "hot" to "delete" based on size (e.g., 5GB) or age (e.g., 7 days), preventing disk space issues.

### 34. Kibana Dashboards are demonstrated
* Kibana is deployed in the `logging` namespace using [kibana.yaml]. It connects to Elasticsearch, allowing administrators to filter and view application, container, and system logs.

### 35. Student can describe the process of defining alert rules and routing them through Alertmanager
* **Process**:
  1. Define alert rules containing PromQL expressions in a `PrometheusRule` manifest.
  2. The Prometheus Operator loads these rules and evaluates them.
  3. When an expression resolves to `true` longer than the duration specified in the `for` field, the alert is triggered and sent to Alertmanager.
  4. Alertmanager routes the alert to destinations (such as email, Slack, or Webhooks) based on routing rules.

### 36. Student can show how to configure alerting for frequent pod restarts and implement alert grouping and throttling to reduce alert fatigue
* **Rule**: Uses the expression `increase(kube_pod_container_status_restarts_total[15m]) > 3`.
* **Throttling**: Configured in Alertmanager's settings:
  * `group_by`: Groups identical alerts by namespace or pod name.
  * `group_wait`: Buffers alerts of the same group to send them in one notification.
  * `repeat_interval`: Prevents sending the same notification too frequently (e.g., wait 4 hours before alerting again).

Run this command to see the "secret" alertmanager config:
```
kubectl get secret alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 --decode
```
---

## Part 5: Alerting Verification & Triggers

Alert rules are defined in [prometheus-rules.yaml] and loaded into Prometheus.

### 37. Alert is created for node CPU usage exceeding 80% for more than 5 minutes
* **Rule**: `NodeCPUUsageHigh`
* **Trigger Command**: 
  * **Option 1: Kubernetes-native (Recommended)**. Run a temporary container on the cluster to consume host CPU (no SSH needed, runs in `default` namespace to bypass `vitals-app` resource quota restrictions):
    ```bash
    kubectl run node-cpu-stress --image=polinux/stress-ng --restart=Never -- --cpu 4 --timeout 310s
    ```
  * **Option 2: SSH Native Loop**. SSH into Minikube and run a loop using native `dd` (since `stress-ng` is not pre-installed on the host VM):
    ```bash
    minikube ssh -- "timeout 310 dd if=/dev/zero of=/dev/null & timeout 310 dd if=/dev/zero of=/dev/null & timeout 310 dd if=/dev/zero of=/dev/null & timeout 310 dd if=/dev/zero of=/dev/null"
    ```

### 38. Alert is created for node available disk space falling below 20%
* **Rule**: `NodeDiskSpaceLow`
* **Trigger Command**: SSH into the Minikube VM and create a large dummy file (using `sudo` to write to root directory):
  ```bash
  minikube ssh -- sudo fallocate -l 10G /large_file.img
  ```
  *(Cleanup command: `minikube ssh -- sudo rm -f /large_file.img`)*

This alert didn't work on my Mac, but this is actually a very interesting system behavior:

Why it didn't fire (The 1 Terabyte Mac Disk): 
If we check the disk size inside my Minikube container VM by running df -h /, here is the output:

text
Filesystem      Size  Used Avail Use% Mounted on
overlay        1007G   25G  932G   3% /
Because Minikube is running with the Docker driver on my Mac:

The container shares my Mac's actual hard drive capacity, which reports a massive 1 Terabyte (1007 GB) of disk space!
The current usage is only 3% (meaning 97% is free space).
To make the free space drop below the 20% threshold (less than ~200GB free), we would need to create a dummy file of over 730 Gigabytes!

BUT I CANNOT allocate a 750GB file! Doing so will write directly to my Mac's physical hard drive, fill up my actual storage, and could crash my Mac's operating system!

The Safe Testing Solution (Threshold Simulation)
In containerized local clusters, the standard industry practice to test disk space alerts safely is threshold simulation (temporarily raising the trigger threshold to match the current state).

Since my current free space is 97%, we can temporarily configure the alert to trigger if free space falls below 98% (which it currently is, since 97% < 98%):

So what I did: 
Open my `manifests/prometheus-rules.yaml`
Go to line 21 (the `NodeDiskSpaceLow` alert):
```yaml
expr: (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
```
Change the `< 20` to `< 98`:
```yaml
expr: (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 98
```
Apply the updated rule in my terminal:
```bash
kubectl apply -f manifests/prometheus-rules.yaml
```

Go to the Prometheus Alerts UI at `http://localhost:9191/alerts`.
Within 1 minute (the `for: 1m` duration in the rule), the `NodeDiskSpaceLow` alert will turn Yellow (Pending) and then Red (Firing)!
Once I am done verifying, I changed the rule back to `< 20` in `manifests/prometheus-rules.yaml` and ran the apply command again

### 39. Alert is created for node memory usage exceeding 90% for more than 5 minutes
* **Rule**: `NodeMemoryUsageHigh`
* **Trigger Command**:
  * **Option 1: Kubernetes-native (Recommended)**. Run a temporary container on the cluster to consume host RAM (no SSH needed, runs in `default` namespace to bypass `vitals-app` resource quota restrictions):
    ```bash
    kubectl run node-mem-stress --image=polinux/stress-ng --restart=Never -- --vm 1 --vm-bytes 5G --timeout 310s
    ```
  * **Option 2: SSH Memory Allocation**. SSH into Minikube and run a python memory allocation:
    ```bash
    minikube ssh -- "python3 -c 'import time; a = bytearray(5 * 1024 * 1024 * 1024); time.sleep(310)'"
    ```

### 40. Alert is created for a pod restarting more than 3 times in 15 minutes
* **Rule**: `PodFrequentlyRestarting`
* **Trigger Command**: Deploy a crash-looping pod:
  ```bash
  kubectl run crashy-pod --image=alpine -n vitals-app -- /bin/sh -c "sleep 5; exit 1"
  ```

### 41. Alert is created for container memory usage exceeding 80% of its limit
* **Rule**: `PodMemoryLimitExceeded`
* **Trigger Command**: Apply a manifest with defined memory limits and run memory-intensive operations (exceeding 80% of its limit but staying below 100% to avoid immediate OOMKills):
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: memory-stress-pod
    namespace: vitals-app
  spec:
    containers:
    - name: stress-ng
      image: polinux/stress-ng
      command: ["stress-ng"]
      args: ["--vm", "1", "--vm-bytes", "100M", "--timeout", "310s"]
      resources:
        limits:
          memory: "120Mi"
        requests:
          memory: "64Mi"
  ```
  *Apply command*: `kubectl apply -f memory-stress-pod.yaml`

### 42. Alert is created for a pod being in a pending state for more than 5 minutes
* **Rule**: `PodStuckInPending`
* **Trigger Command**: Deploy a pod requesting more memory than the cluster can allocate:
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: pending-pod
    namespace: vitals-app
  spec:
    containers:
    - name: app
      image: nginx
      resources:
        requests:
          memory: "128Gi"
  ```
  *Apply command*: `kubectl apply -f pending-pod.yaml`

### 43. Alert is created for the Kubernetes API server becoming unreachable
* **Rule**: `KubernetesAPIServerDown`
* **Trigger Command**: Pause the API server docker container on the host:
  ```bash
  docker pause $(docker ps -q -f name=k8s_kube-apiserver)
  ```

### 44. Alert is created for Elasticsearch cluster status changing to yellow or red
* **Alert Design**: Since we run a single-node Elasticsearch cluster for local testing under resource limits, the status remains `green` (or `yellow` if index replicas are unassigned). To set up automated alerting in a production multi-node cluster, we deploy `elasticsearch-exporter` to export metrics to Prometheus, and define a `PrometheusRule` checking `elasticsearch_cluster_status{color=~"red|yellow"} == 1`.
* **Testing / Query Command**: Query health status using curl:
  ```bash
  kubectl exec -it -n logging deployment/elasticsearch -- curl -s http://localhost:9200/_cluster/health
  ```

### 45. Alert is created for Fluentd log collection errors
* **Alert Design**: To alert on Fluent Bit log collection errors, enable Fluent Bit's built-in HTTP server and metrics endpoint in its ConfigMap (`HTTP_Server On`, `HTTP_Port 2020`), configure a `ServiceMonitor` for Fluent Bit, and define a `PrometheusRule` alert based on `rate(fluentbit_output_errors_total[5m]) > 0`.
* **Testing / Trigger Command**: Modify the Fluent Bit configuration to direct output to an invalid Elasticsearch endpoint:
  ```bash
  kubectl edit configmap fluent-bit-config -n logging
  # change Host to "invalid-host"
  kubectl rollout restart daemonset fluent-bit -n logging
  ```
  *Verify logs using*:
  ```bash
  kubectl logs -l k8s-app=fluent-bit -n logging --tail=50
  ```

---

## Part 6: Cluster Security & Debugging

### 46. Student can explain the importance of RBAC in Kubernetes setup and provide examples
* **Importance**: RBAC enforces the principle of least privilege. It ensures users and service accounts only have the permissions necessary to perform their roles, preventing accidental or malicious cluster-wide modifications.
* **Examples**:
  * Jenkins runs with `jenkins-sa` which is restricted to deploying applications only inside the `vitals-app` namespace via a RoleBinding.
  * The Prometheus scraper runs with a read-only ServiceAccount that can only perform `get`, `list`, and `watch` on endpoints and pods.

### 47. Student can explain the network segmentation within the cluster and provide examples
* **Explanation**: Network segmentation isolates logical domains of the cluster. Workloads should only communicate with explicitly allowed entities.
* **Examples**:
  * We use distinct namespaces (`vitals-app`, `monitoring`, `logging`) to isolate environments.
  * Ingress controllers are isolated in the `ingress-nginx` namespace and route traffic explicitly to defined services only.
  * NetworkPolicies block non-frontend pods from calling the backend REST API directly.

### 48. Student can explain the use of Kubernetes Secrets for storing sensitive data
* **Explanation**: Secrets prevent credentials (API keys, database passwords) from being hardcoded in container images or manifest files.
* **Security note**: By default, secrets are only Base64-encoded, which is not encryption. They must be coupled with etcd encryption-at-rest and RBAC restrictions to prevent unauthorized decodes.

### 49. Student can show how to mount Secrets as volumes or environment variables in pods
* **As Environment Variables**: Shown in [backend-deployment.yaml](file:///Users/williamle/my_cloud_project/kood-sisu/cluster-chronicles/manifests/backend-deployment.yaml):
  ```yaml
  env:
  - name: PORT
    valueFrom:
      secretKeyRef:
        name: vitals-secret
        key: BACKEND_PORT
  ```
* **As Volumes**:
  ```yaml
  volumeMounts:
  - name: secret-volume
    mountPath: "/etc/secrets"
    readOnly: true
  volumes:
  - name: secret-volume
    secret:
      secretName: vitals-secret
  ```

### 50. No sensitive information (API keys, passwords, ssh keys, etc) is exposed in plain text in configuration files or manifests
* Verified: Plaintext values are moved to [secret.yaml](file:///Users/williamle/my_cloud_project/kood-sisu/cluster-chronicles/manifests/secret.yaml) as Base64 encoded values.

### 51. Appropriate namespaces are created for different components of the application
* Application workload resides in `vitals-app`.
* Observability tools reside in `monitoring` and `logging`.

### 52. Student can walk through the process for debugging a pod stuck in a CrashLoopBackOff state and describe the commands used and what to look for
* **Process**:
  1. Retrieve pod status: `kubectl get pods -n vitals-app`
  2. Inspect pod configuration and events: `kubectl describe pod <pod-name> -n vitals-app` (check the bottom events section for failures like mounting volumes or configuration errors).
  3. Retrieve logs from the current crashed instance: `kubectl logs <pod-name> -n vitals-app`
  4. Retrieve logs from the *previous* crashed instance: `kubectl logs <pod-name> -n vitals-app --previous`
  5. Check config maps, secrets, and database connectivity.

### 53. Student can explain how to diagnose and resolve a situation where pods are stuck in a Pending state due to insufficient cluster resources
* **Diagnosis**:
  1. Inspect scheduling failures: `kubectl describe pod <pod-name> -n vitals-app` (look for `FailedScheduling` events showing `"Insufficient memory"` or `"Insufficient cpu"`).
  2. Check node capacity and allocation: `kubectl describe nodes` or `kubectl top nodes` to see available allocatable memory/CPU.
  3. Check namespace quotas: `kubectl get resourcequota -n vitals-app`.
* **Resolution**:
  * Reduce pod requests/limits in deployment files if they are set unnecessarily high.
  * Increase cluster capacity by scaling node pools (in cloud environments) or allocating more resources to the local VM (e.g., `minikube start --cpus 4 --memory 8192`).

### 54. Folder structure logically separates manifests, scripts, CI/CD configurations and other project related files
* Verified:
  * manifests/ contains all Kubernetes resource definitions.
  * docs/ contains study guides, guides, and tutorials.
  * backend/ and frontend/ contain application source code.
  * root contains README, walkthrough logs, and Jenkinsfile.

### 55. The README file contains a clear project overview, setup instructions, and usage guide
* Located in [README.md](file:///Users/williamle/my_cloud_project/kood-sisu/cluster-chronicles/README.md).

### 56. The code is well-organized, properly commented, and follows best practices for the chosen programming language(s)
* Verified: Go backend code ([main.go]) is formatted, structured, and properly commented.

---

## Part 7: Advanced Extra Requirements

### 57. Student can explain the purpose and process of integrating the image scanning tool into the CI/CD pipeline
* **Purpose**: Automate container security audits. By scanning the image before deploying it, we identify known vulnerabilities (CVEs) in OS base layers and third-party packages, preventing compromised code from reaching the cluster.
* **Process**:
  1. Define a security agent container running Trivy (`aquasec/trivy:latest`) in the Jenkins pod agent template.
  2. Compile and build the container image.
  3. Run the scan command on the target image during the build pipeline.
  4. Block deployment and fail the pipeline (e.g. using `exit-code 1`) if high or critical vulnerabilities are discovered.

### 58. Image scanning tool is configured to scan images before deployment
* Integrated in [Jenkinsfile.k8s]:
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
* **How to test**: Run the Jenkins pipeline and inspect the console log output. Verify that the `Security Scan (Trivy)` stage runs, fetches the CVE database, scans `vitals-backend:latest`, outputs a tabular report, and exits successfully before the deployment stage.

### 59. HPA configuration is demonstrated and described how it interacts with the frontend deployment
* Deployed via [hpa.yaml].
  * **Configuration**: Targets the `vitals-frontend` deployment, maintaining a minimum of 2 and a maximum of 5 replicas.
  * **Interaction**: The HPA controller queries the **Metrics Server** every 15 seconds to fetch average CPU utilization. If the average CPU utilization across all frontend pods exceeds 50%, the HPA calculates the desired replicas and triggers the deployment controller to spin up new pods.
* **How to test**: Verify the HPA is active:
  ```bash
  kubectl get hpa -n vitals-app
  ```
  

### 60. Scaling behavior is demonstrated by showing the increase and decrease in the number of pods based on the load
* **Scale-up Process**:
  1. Start monitoring in two separate terminal windows:
     ```bash
     kubectl get hpa -n vitals-app -w
     # and:
     kubectl get pods -n vitals-app -w
     ```
  2. Generate heavy traffic using a temporary load-generator pod:
     ```bash
     kubectl run load-generator --image=busybox -n vitals-app --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://vitals-frontend-service:3000/; done"
     ```
  3. Observe the CPU utilization metric rise in the HPA console. Once it crosses 50%, the HPA triggers a scale-up, and you will see new frontend pods transitioning to `Running`.
* **Scale-down Process**:
  1. Stop the load generator:
     ```bash
     kubectl delete pod load-generator -n vitals-app
     ```
  2. Observe CPU utilization return to normal. After a stabilization window (defaulting to 5 minutes to prevent thrashing), the HPA automatically terminates extra pods, scaling down back to 2 replicas.

### 61. Student has implemented additional technologies, security enhancements and/or features beyond the core requirements
* **Advanced Implementations**:
  1. **Kaniko Daemonless Builds**: Built Docker images using Kaniko in [Jenkinsfile.k8s] (`gcr.io/kaniko-project/executor:debug`). This eliminates the requirement to mount the host's `/var/run/docker.sock`, securing the node against container escape exploits.
  2. **Memory-Optimized Stack**: Fine-tuned JVM parameters for Elasticsearch (`-Xms128m -Xmx256m`) and memory limits for Kibana/monitoring tools, enabling the entire logging, alerting, CI/CD, and application stack to run locally on a single 6GB Minikube cluster.
  3. **Custom ServiceMonitor Metrics**: Integrated custom application metrics (`app_cpu_usage_percent` and `app_memory_used_mb`) into Prometheus scraping using CRD ServiceMonitor selectors instead of basic static config endpoints.
  4. **Strict RBAC Controls**: Confined the CI/CD pipeline's access permissions to a single namespace (`vitals-app`) using Role-Based Access Control, rather than granting cluster-wide cluster-admin access.
* **How to test**: Verify that the manifests in `/manifests/` are loaded, and run the commands described in this document to demonstrate active components.