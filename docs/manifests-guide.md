# Master Guide: Writing Kubernetes Manifests From Scratch
This document serves as a quick reminder on how to write Kubernetes manifests. Writing K9s manifests doesn't require memorization. It requires understanding the **YAML syntax rules**, the **four metadata keys**, and the **spec patterns**. This guide breaks down the files I wrote in `/manifests` and provides blueprints for future reference (as in similar projects in the future)
---

## Part 1: YAML Syntax Rules for Kubernetes
Kubernetes uses YAML (YAML Ain't Markup Language). It is strictly space-sensitive. 

### Rule 1: Spaces, Never Tabs
* Indentations must be **spaces** (usually 2 spaces per indentation level).
* Using a Tab character will throw a validation error.

### Rule 2: Keys and Lists
* **Key-Value Maps**: Denoted by `key: value`. Note the space after the colon.
  ```yaml
  name: vitals-backend
  ```
* **Lists / Arrays**: Denoted by a leading dash `-`. Items in a list are indented at the same level.
  ```yaml
  containers:
  - name: backend
    image: vitals-backend:latest
  - name: frontend
    image: vitals-frontend:latest
  ```

### Rule 3: Multi-Document Files
* Multiple Kubernetes resources can be combined into a single YAML file by separating them with three dashes `---`.
  ```yaml
  apiVersion: v1
  kind: Service
  # ... (service 1)
  ---
  apiVersion: v1
  kind: Service
  # ... (service 2)
  ```

---
## Part 2: The Core Structure of Every Manifest
Every Kubernetes YAML file must declare four root-level keys:

```yaml
apiVersion: group/version  # Which API group maps to this resource
kind: ResourceType         # What type of object are we creating (Pod, Service, etc.)
metadata:                  # Information that uniquely identifies the object
  name: my-resource
  namespace: my-namespace
  labels:
    app: my-app
spec:                      # The desired state of the resource (what goes inside)
  # ...
```

---

## Part 3: Purpose & Structure of Our Manifest Files

Here is the breakdown of the files I have deployed in this project, their purpose, and how their sections operate:

### 1. Namespace (`namespace.yaml`)
* **Purpose**: Creates isolated virtual environments in the cluster.
* **Blueprint**:
  ```yaml
  apiVersion: v1
  kind: Namespace
  metadata:
    name: vitals-app
  ```
* My own notes: think of this as creating a virtual folder within the cluster for an app's resources. All the resources for the app will be stored in this folder. This helps keep your cluster organized and makes it easier to manage your apps.

### 2. ConfigMap (`configmap.yaml`)
* **Purpose**: Stores non-sensitive, environment-specific configuration values in plain text.
* **Key Option**:
  * `data`: Key-value pairs containing strings.
* **Blueprint**:
  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: vitals-config
    namespace: vitals-app
  data:
    BACKEND_URL: "http://vitals-backend-service:8080"
  ```

### 3. Secret (`secret.yaml`)
* **Purpose**: Stores sensitive parameters (API keys, passwords, ports).
* **Key Options**:
  * `type: Opaque`: General key-value secret.
  * `data`: All values **must** be Base64 encoded.
* **Command to encode**: `echo -n "8080" | base64` (returns `ODA4MA==`).
* **Blueprint**:
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: vitals-secret
    namespace: vitals-app
  type: Opaque
  data:
    BACKEND_PORT: "ODA4MA=="
  ```

### 4. Deployment (`backend-deployment.yaml` / `frontend-deployment.yaml`)
* **Purpose**: Manages stateless Pods, replicas, rolling updates, and container configurations.
* **Crucial Structure Elements**:
  * `replicas`: Number of identical pods to run.
  * `selector`: Tells the deployment which pods to manage (must match `template.metadata.labels`).
  * `template`: The blueprint for the Pods.
    * `containers`: List of containers running inside the Pod.
      * `imagePullPolicy: Never`: Forces Minikube to use local host images instead of pulling from Docker Hub.
      * `resources`:
        * `requests`: Minimum guaranteed resources.
        * `limits`: CPU/RAM caps.
      * `livenessProbe` / `readinessProbe`: Health check HTTP or TCP endpoints.

* **Blueprint**:
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: app-deployment
    namespace: vitals-app
  spec:
    replicas: 2
    selector:
      matchLabels:
        app: app-label
    template:
      metadata:
        labels:
          app: app-label
      spec:
        containers:
        - name: app-container
          image: my-image:latest
          ports:
          - containerPort: 3000
            name: http
          env:
          - name: BACKEND_URL          # Injects value from ConfigMap
            valueFrom:
              configMapKeyRef:
                name: vitals-config
                key: BACKEND_URL
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
  ```

### 5. Service (`services.yaml`)
* **Purpose**: Defines a stable IP address and DNS entry that routes traffic to pods matching the label selector.
* **Key Options**:
  * `type`: `ClusterIP` (internal, default), `NodePort` (accessible on host ports 30000-32767), or `LoadBalancer` (cloud ingress).
  * `targetPort`: The port the application container is listening on.
  * `port`: The port the Service itself exposes.
* **Blueprint**:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: app-service
    namespace: vitals-app
  spec:
    type: ClusterIP
    selector:
      app: app-label           # Must match Pod template labels
    ports:
    - name: http
      protocol: TCP
      port: 80                 # Service port
      targetPort: 3000         # Container port
  ```

### 6. Ingress (`ingress.yaml`)
* **Purpose**: Acts as an HTTP/HTTPS reverse proxy, routing external domain requests to internal services.
* **Key Options**:
  * `rules`: List of routing hosts (e.g. `vitals.local`).
  * `pathType: Prefix`: Routes any path starting with `/` to the backing service.
* **Blueprint**:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: app-ingress
    namespace: vitals-app
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "false"
  spec:
    rules:
    - host: vitals.local
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: app-service
              port:
                number: 80
  ```

### 7. Persistent Volume & Claim (`storage.yaml`)
* **Purpose**: Mounts persistent storage directories that persist beyond container lifecycles.
* **PV Spec**: References absolute storage locations (e.g., node disk directories).
* **PVC Spec**: Namespace-level reservation requests matching storage size and className.
* **Blueprint**:
  ```yaml
  apiVersion: v1
  kind: PersistentVolume
  metadata:
    name: app-pv
  spec:
    capacity:
      storage: 5Gi
    accessModes:
    - ReadWriteOnce
    storageClassName: manual
    hostPath:
      path: /data/app-storage
  ---
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: app-pvc
    namespace: vitals-app
  spec:
    storageClassName: manual
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 5Gi
  ```
