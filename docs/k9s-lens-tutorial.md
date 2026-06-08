# Visualizing Kubernetes: K9s & Lens Tutorial

This guide provides a quick-start reference and cheatsheet for navigating and troubleshooting your Kubernetes clusters using two of the most popular tools in the DevOps industry: **K9s** (CLI-based terminal UI) and **Lens** (Desktop GUI application).

---

## Prerequisites
Both tools run by reading your local **Kubeconfig** file (default path: `~/.kube/config`).
* When you run `minikube start`, your context is automatically set to `minikube`.
* Open either tool, and it will immediately detect your Minikube cluster.

---

## ⌨1. K9s: The Terminal Wizard
K9s is a terminal UI (TUI) tool. It uses keyboard shortcuts and commands (similar to Vim) to navigate resources at lightning speed.

### Getting Started
Open your terminal and launch K9s:
```bash
k9s
```

### Navigation Shortcuts
* `Enter` - View details of the highlighted item (e.g. view pods inside a Deployment, or containers inside a Pod).
* `Esc` - Go back to the previous screen.
* `j` / `k` (or `Up` / `Down` arrows) - Scroll up and down.

### The Command Menu (Colons `:`)
Just like in Vim, press `:` to open the command prompt. Type the command and press `Enter`:
* `:ns` - View and switch **Namespaces** (e.g. select `vitals-app`).
* `:pods` or `:po` - View all **Pods**.
* `:deploy` or `:dp` - View all **Deployments**.
* `:svc` - View all **Services**.
* `:ingress` or `:ing` - View all **Ingress** configurations.
* `:pv` / `:pvc` - View **Persistent Volumes** and **Claims**.
* `:hpa` - View **Horizontal Pod Autoscalers**.
* `:all` - View all resources in the active namespace.

### Action Shortcuts (Perform actions on highlighted items)
Highlight a resource (like a Pod) and press:
* `l` - Show live **Logs**. (Use `0` to view all logs, `f` to toggle auto-scroll/follow, `Esc` to exit logs).
* `s` - **Shell** into the container (opens a live bash/sh terminal inside the Pod). Type `exit` to close.
* `d` - **Describe** the resource (equivalent to `kubectl describe`, showing YAML status and errors).
* `e` - **Edit** the live YAML file on the fly (uses your default terminal editor like Vim/Nano).
* `Ctrl + D` - **Delete** (kill) the selected Pod or resource. (Useful for testing self-healing!).

---

## 2. Lens: The Desktop IDE
Lens is a graphical desktop application. It is excellent for visual mapping, performance charts, and multi-cluster management.

### Getting Started
1. Open the **Lens** app.
2. In the left-side catalog, click on **minikube** (Lens automatically imports it from `~/.kube/config`).

### Key Interactive Areas

#### 1. The Namespace Selector
* Located at the top right of the dashboard.
* Click it and select **vitals-app** or **monitoring**. This filters out system pods (like DNS or kubernetes core) so you can focus only on your application code.

#### 2. The Sidebar Navigation
* **Workloads** -> **Pods**: Displays the status, age, and CPU/Memory usage of every running container.
* **Workloads** -> **Deployments**: Displays the replica count (e.g., `2/2` for frontend) and rollout status.
* **Config** -> **ConfigMaps / Secrets**: View configuration details (secrets are hidden behind a "show" button so they are safe from shoulder-surfing).
* **Storage** -> **Persistent Volume Claims**: Tracks if storage is `Bound`, `Pending`, or disconnected.

#### 3. Pod Action Icons (Top-Right of Details Pane)
Click on any Pod to open its detailed sidebar, then look at the top-right icons:
* **`>_` (Terminal Icon)**: Opens a terminal shell inside the running container directly at the bottom of the Lens window.
* **Document Icon (Logs)**: Opens a streaming window of container logs. You can search, pause, or download logs directly from here.
* **Trash Can Icon**: Deletes/Terminates the pod.

---

## Summary: When to use which?
* Use **K9s** for quick developer tasks, tailing logs, shelling into pods, and quick sanity checks. It takes up zero screen real estate and keeps you in flow.
* Use **Lens** for diagnosing cluster health (CPU/Memory limits), viewing charts, managing multiple clusters, or editing complex YAML properties visually.
