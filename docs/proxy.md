# Proxy, but what is it really? and what is reverse proxy by the way?
This document serves to explain more about the concept of proxy and reverse proxy.

Think of a **proxy** as “someone making a request on your behalf,” and a **reverse proxy** as “someone receiving requests on behalf of your servers.”
The direction matters.
---
# 1. Regular Proxy (Forward Proxy)
A **forward proxy** sits between a **client** and the internet.
Flow:
```text
You → Proxy → Internet
```

Example:
```text
Laptop → Corporate Proxy → google.com
```

The destination server sees the **proxy’s IP**, not yours.

## Why companies use it
* Internet filtering
* Monitoring employee traffic
* Caching websites
* Hiding internal IPs
* Security policies

## DevOps example
A VM inside a private network cannot access the internet directly.
So you configure:
```bash
export HTTP_PROXY=http://proxy.company.local:8080
```
Now:
```text
VM → proxy.company.local → Internet
```
Very common in:
* corporate Kubernetes clusters
* CI/CD runners
* air-gapped environments
* enterprise cloud setups
---

# 2. Reverse Proxy
A **reverse proxy** sits in front of **servers**.
Flow:
```text
Internet → Reverse Proxy → Your App Servers
```

Example:
```text
User → NGINX → Node.js app
```

The client thinks it’s talking to one server, but the reverse proxy forwards traffic internally.

---

# Why reverse proxies are HUGE in DevOps
They handle:
* SSL/TLS termination
* Load balancing
* Routing
* Authentication
* Rate limiting
* Caching
* Hiding internal services
---
# Kubernetes Perspective
This is where it becomes important.
---
## Without reverse proxy

Suppose you have 3 app pods:

```text
pod-1
pod-2
pod-3
```

Users cannot directly access pods safely.

You need something in front.

---

## With reverse proxy

```text
Internet
   ↓
Ingress Controller (NGINX)
   ↓
Kubernetes Service
   ↓
Pods
```

The Ingress Controller acts like a reverse proxy.

---

# Kubernetes Components Mapping

| Component          | Role                    |
| ------------------ | ----------------------- |
| Ingress Controller | Reverse proxy           |
| Service            | Internal load balancer  |
| Pod                | Actual app              |
| kube-proxy         | Network traffic routing |
| API Gateway        | Advanced reverse proxy  |

---

# Real Kubernetes Example

User visits:

```text
https://api.myapp.com/users
```

Flow:

```text
Internet
  ↓
NGINX Ingress
  ↓
users-service
  ↓
users-pod-1
```

NGINX decides:

* where traffic goes
* which pod receives it
* HTTPS handling
* path routing

---

# VM World Example

Traditional setup:

```text
Internet
   ↓
NGINX Reverse Proxy VM
   ↓
App VM 1
App VM 2
Database VM
```

The reverse proxy:

* exposes only one public IP
* distributes requests
* protects backend servers

---

# Easy Mental Model

## Forward Proxy

> “Go fetch this website for me.”

Client-side.

---

## Reverse Proxy

> “I’ll receive requests and decide which server should handle them.”

Server-side.

---

# Famous Proxy Technologies

## Forward Proxies

* Squid
* TinyProxy

---

## Reverse Proxies

* NGINX
* HAProxy
* Traefik
* Envoy

---

# In Kubernetes Specifically

Most modern Kubernetes networking is basically:

```text
Reverse proxies + service discovery + load balancing
```

Examples:

* Ingress Controller = reverse proxy
* Service Mesh = smart proxies everywhere
* API Gateway = programmable reverse proxy

---

# Service Mesh (advanced)

With tools like:

* Istio
* Linkerd

Every pod gets a tiny proxy sidecar.

```text
App Container ↔ Envoy Proxy ↔ Network
```

This enables:

* mTLS
* retries
* observability
* traffic shaping
* zero-trust networking

---

# One-Line Summary

## Proxy (forward proxy)

Protects/hides the **client**.

```text
Client → Proxy → Internet
```

---

## Reverse Proxy

Protects/manages the **servers**.

```text
Internet → Reverse Proxy → Backend Servers
```
---
# The DevOps Interview Version
If someone asks:

> “What is a reverse proxy in Kubernetes?”
Good answer:
> “A reverse proxy receives external traffic and routes it to internal services or pods. In Kubernetes, Ingress Controllers like NGINX commonly act as reverse proxies handling TLS termination, routing, and load balancing.”


Deep Dive: The Nginx Ingress Controller
A. What is its job?
In Kubernetes, Pods and default Services are isolated inside a private network cluster. External browsers cannot reach them. The Ingress Controller acts as the gateway. It is a reverse proxy and load balancer running inside the cluster.

Its job is to watch the Kubernetes API. When you deploy a new Ingress rule manifest (e.g. mapping vitals.local to vitals-frontend-service), the Ingress Controller intercepts that manifest, dynamically updates its internal Nginx routing configurations, and reload-configures itself without downtime.

B. Practical Knowledge for Production
In real-life enterprise environments, the Ingress Controller is the most critical edge component:

TLS Termination (HTTPS): Instead of configuring SSL/TLS certificates inside every separate application container, you load certificates into Kubernetes Secrets and attach them to the Ingress controller. The Ingress decrypts HTTPS requests at the edge and forwards plain HTTP traffic internally to your services, simplifying certificate management (using tools like Let's Encrypt / cert-manager) and saving CPU.
Routing Rules (L7 HTTP Layer): It handles path routing (e.g., vitals.com/api goes to the backend service, while vitals.com/ goes to the React frontend service) and host-name routing.
Advanced Annotations: In production, you modify how the controller behaves by adding annotations to your Ingress manifest. Common examples:
URL Rewriting: nginx.ingress.kubernetes.io/rewrite-target: /$2 (hides path differences).
Rate Limiting: nginx.ingress.kubernetes.io/limit-connections: "20" (protects against DDoS).
Client Body Limits: nginx.ingress.kubernetes.io/proxy-body-size: "10m" (restricts maximum file upload sizes).
Integration with Cloud Load Balancers: In public clouds, installing an Ingress Controller automatically provisions an external cloud load balancer (like AWS Network Load Balancer) that routes all internet port 80/443 traffic directly to the Ingress Controller pods.