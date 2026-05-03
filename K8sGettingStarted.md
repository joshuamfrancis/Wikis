# Kubernetes One-Day Learning Plan
## Two-Node Cluster: Desktop (Control Plane) + Laptop (Worker Node)

> **Goal:** By end of day, you will have a working 2-node Kubernetes cluster running real services with HA, load balancing, secrets management, manual and automated deployments.

---

## Your Environment

| Machine | Role | OS |
|---|---|---|
| Desktop | Control Plane (Master) | Ubuntu 26.04 Desktop |
| Laptop | Worker Node | Ubuntu 26.06 Server |

**Services you'll host:** REST API (2 replicas, HA), with a path toward InfluxDB, Grafana, and Cloudflared tunnels.

---

## Overview: Day Structure

| Block | Time Estimate | Topic |
|---|---|---|
| Block 1 | ~1.5 hrs | Concepts + cluster installation |
| Block 2 | ~1 hr | Namespaces, deployments, services, load balancer |
| Block 3 | ~45 min | Secrets & ConfigMaps |
| Block 4 | ~1.5 hrs | Local dev, validation, manual deploy workflow |
| Block 5 | ~1 hr | Automated deployment (GitHub Actions CI/CD) |
| Block 6 | ~30 min | Validation, troubleshooting, next steps |

---

## Block 1 — Concepts & Cluster Installation (~1.5 hrs)

### 1.1 Core Concepts (15 min read)

Before touching a terminal, understand these primitives:

- **Node** — A physical/virtual machine in the cluster. Your desktop = control plane node. Your laptop = worker node.
- **Pod** — The smallest deployable unit. One or more containers running together on a node.
- **Deployment** — Declares desired state (e.g., "I want 2 replicas of this container"). Kubernetes maintains it.
- **Service** — A stable network endpoint in front of pods. Pods come and go; Services provide a consistent IP/DNS name.
- **LoadBalancer / NodePort** — Service types that expose apps externally.
- **Namespace** — Virtual cluster within a cluster. Used to isolate workloads (similar to your VLAN concept).
- **ConfigMap** — Key-value configuration injected into pods without rebuilding images.
- **Secret** — Same as ConfigMap but base64-encoded and treated with restricted access.
- **Ingress** — HTTP routing rules (like a reverse proxy) in front of Services.
- **kubectl** — The CLI tool you'll use for everything.

**Mental model:** `Deployment` manages `ReplicaSet` → manages `Pods` → exposed by `Service` → optionally routed by `Ingress`.

---

### 1.2 Prerequisites on Both Machines

Run the following on **both desktop and laptop** before installing Kubernetes.

```bash
# Disable swap (Kubernetes requires this)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Verify swap is off
free -h
# Swap line should show 0

# Enable required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set required sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Verify
lsmod | grep br_netfilter
lsmod | grep overlay
```

---

### 1.3 Install Container Runtime (containerd) — Both Machines

```bash
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Generate default config
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable SystemdCgroup (required for kubeadm)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and enable
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify
sudo systemctl status containerd
```

---

### 1.4 Install kubeadm, kubelet, kubectl — Both Machines

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes apt repository (v1.32 — latest stable)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Pin versions so they don't auto-upgrade and break things
sudo apt-mark hold kubelet kubeadm kubectl

# Verify
kubectl version --client
kubeadm version
```

---

### 1.5 Initialise the Control Plane — Desktop Only

```bash
# Find your desktop's primary IP (use the interface connected to your home network)
ip addr show
# Note the IP — replace 192.168.x.x below with your actual desktop IP

# Initialise the cluster
# --pod-network-cidr is required for Flannel CNI
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<YOUR_DESKTOP_IP>

# IMPORTANT: Save the 'kubeadm join' command printed at the end — you'll need it for the laptop
```

After init completes, configure kubectl for your user:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify the control plane is running
kubectl get nodes
# Status will be 'NotReady' until CNI is installed
```

---

### 1.6 Install CNI Network Plugin (Flannel) — Desktop Only

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait ~60 seconds then check
kubectl get nodes
# Desktop should now show 'Ready'

kubectl get pods -n kube-flannel
# All pods should be Running
```

---

### 1.7 Join the Worker Node — Laptop Only

Use the `kubeadm join` command that was printed during `kubeadm init`. It looks like:

```bash
sudo kubeadm join <DESKTOP_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

If you lost the join command, regenerate it on the desktop:

```bash
# On desktop
kubeadm token create --print-join-command
```

**Verify from desktop:**

```bash
kubectl get nodes
# Both nodes should show 'Ready'
# NAME        STATUS   ROLES           AGE   VERSION
# desktop     Ready    control-plane   5m    v1.32.x
# laptop      Ready    <none>          1m    v1.32.x
```

Label the worker node:

```bash
kubectl label node <laptop-hostname> node-role.kubernetes.io/worker=worker
```

---

## Block 2 — Deployments, Services & Load Balancer (~1 hr)

### 2.1 Install MetalLB (Software Load Balancer)

Kubernetes' `LoadBalancer` service type requires a cloud provider by default. On bare metal, use MetalLB.

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for MetalLB pods to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

Configure MetalLB with an IP range from your home network that is **outside your DHCP range**. For example, if your router hands out 192.168.1.100–199, you might use 192.168.1.200–210 for MetalLB.

```bash
# Create MetalLB IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: home-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.210   # <-- Adjust to your network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: home-l2
  namespace: metallb-system
EOF
```

---

### 2.2 Create Your First Namespace

Namespaces isolate workloads. You'll use `apps` for your services.

```bash
kubectl create namespace apps

# List namespaces
kubectl get namespaces
```

---

### 2.3 Deploy a REST API with High Availability (2 Replicas)

We'll use a simple demo REST API (`kennethreitz/httpbin`) as a stand-in for your services. The pattern is identical for your own Python API.

Create the file `api-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-api
  namespace: apps
  labels:
    app: demo-api
spec:
  replicas: 2                         # HA: 2 instances
  selector:
    matchLabels:
      app: demo-api
  strategy:
    type: RollingUpdate               # Zero-downtime updates
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    metadata:
      labels:
        app: demo-api
    spec:
      containers:
      - name: api
        image: kennethreitz/httpbin
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        readinessProbe:               # Only send traffic when container is ready
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:                # Restart container if it becomes unhealthy
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
      topologySpreadConstraints:      # Spread pods across both nodes
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: demo-api
```

Apply it:

```bash
kubectl apply -f api-deployment.yaml

# Watch pods appear on both nodes
kubectl get pods -n apps -o wide -w

# You should see 2 pods, ideally one per node
```

---

### 2.4 Expose the Deployment with a LoadBalancer Service

Create `api-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-api-svc
  namespace: apps
spec:
  type: LoadBalancer                  # MetalLB will assign an external IP
  selector:
    app: demo-api                     # Matches the deployment's pod labels
  ports:
  - protocol: TCP
    port: 80                          # External port
    targetPort: 80                    # Container port
```

Apply and verify:

```bash
kubectl apply -f api-service.yaml

# Watch for external IP assignment (takes ~30 seconds)
kubectl get svc -n apps -w

# Once EXTERNAL-IP is assigned (e.g., 192.168.1.200):
curl http://192.168.1.200/get
# Should return JSON from httpbin
```

**Understanding what just happened:**

- MetalLB assigned a real IP from your home network pool
- kube-proxy on each node distributes traffic across both pods using iptables rules
- If one pod dies, the other continues serving traffic — this is HA

Verify load balancing across pods:

```bash
# Watch pod logs to see requests hitting different pods
kubectl logs -n apps -l app=demo-api -f --prefix=true
# In another terminal:
for i in $(seq 1 10); do curl -s http://192.168.1.200/get | grep origin; done
```

---

## Block 3 — Secrets & ConfigMaps (~45 min)

### 3.1 Understanding the Difference

| | ConfigMap | Secret |
|---|---|---|
| Use for | Non-sensitive config (URLs, feature flags) | Passwords, API keys, tokens |
| Storage | Plain text in etcd | base64-encoded in etcd |
| Access | Any pod in namespace | Restricted by RBAC |

> **Note:** Kubernetes Secrets are base64-encoded, not encrypted by default. For production, use sealed-secrets or an external vault. For your home lab, this is fine.

---

### 3.2 Create a ConfigMap

```bash
# Create from literal values
kubectl create configmap demo-config \
  --namespace=apps \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info \
  --from-literal=API_BASE_URL=http://demo-api-svc

# View it
kubectl get configmap demo-config -n apps -o yaml
```

---

### 3.3 Create a Secret

```bash
# Create from literal values (Kubernetes handles the base64 encoding)
kubectl create secret generic demo-secret \
  --namespace=apps \
  --from-literal=DB_PASSWORD=mySuperSecretPass123 \
  --from-literal=API_KEY=sk-abc123def456

# View (values are base64 encoded)
kubectl get secret demo-secret -n apps -o yaml

# Decode a value
kubectl get secret demo-secret -n apps -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

---

### 3.4 Inject ConfigMap and Secret into the Deployment

Update `api-deployment.yaml` to add environment variables:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-api
  namespace: apps
  labels:
    app: demo-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    metadata:
      labels:
        app: demo-api
    spec:
      containers:
      - name: api
        image: kennethreitz/httpbin
        ports:
        - containerPort: 80
        env:
        - name: APP_ENV                   # From ConfigMap
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: APP_ENV
        - name: LOG_LEVEL                 # From ConfigMap
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: LOG_LEVEL
        - name: DB_PASSWORD               # From Secret
          valueFrom:
            secretKeyRef:
              name: demo-secret
              key: DB_PASSWORD
        - name: API_KEY                   # From Secret
          valueFrom:
            secretKeyRef:
              name: demo-secret
              key: API_KEY
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /get
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: demo-api
```

Apply and verify the env vars are injected:

```bash
kubectl apply -f api-deployment.yaml

# Exec into a running pod to verify
kubectl exec -n apps -it $(kubectl get pod -n apps -l app=demo-api -o jsonpath='{.items[0].metadata.name}') -- env | grep -E "APP_ENV|LOG_LEVEL|DB_PASSWORD|API_KEY"
```

---

### 3.5 Secret as a Mounted File (Alternative Pattern)

Some apps (like InfluxDB) expect secrets as files, not env vars:

```yaml
# Add to pod spec -> volumes:
volumes:
- name: secret-volume
  secret:
    secretName: demo-secret

# Add to container -> volumeMounts:
volumeMounts:
- name: secret-volume
  mountPath: /etc/secrets
  readOnly: true
```

Files will appear at `/etc/secrets/DB_PASSWORD` and `/etc/secrets/API_KEY`.

---

## Block 4 — Manual Deployment Workflow (~1.5 hrs)

This block covers the complete lifecycle: write code → test locally → containerise → validate container → push → deploy to Kubernetes. Never skip the local validation steps — catching problems early saves significant debugging time in the cluster.

---

### 4.1 Install Local Prerequisites

Before writing any application code, ensure your desktop has the required tools.

```bash
# Install Python 3.12 and pip
sudo apt-get update
sudo apt-get install -y python3.12 python3.12-venv python3-pip

# Verify
python3.12 --version
pip3 --version

# Install Docker (if not already installed)
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to the docker group (avoids needing sudo for docker commands)
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker
docker --version
docker compose version
```

---

### 4.2 Create the Project Structure

```bash
mkdir ~/k8s-demo-api && cd ~/k8s-demo-api

# Create the directory structure
mkdir -p tests

# Verify structure
ls -la
# Should show: main.py  requirements.txt  requirements-dev.txt  Dockerfile  docker-compose.yml  tests/
```

---

### 4.3 Write the Application

Create each file below exactly as shown.

**`main.py`:**

```python
from fastapi import FastAPI
import os

app = FastAPI(title="K8s Demo API", version="1.0.0")

@app.get("/")
def root():
    return {
        "message": "Hello from Kubernetes!",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "env": os.getenv("APP_ENV", "unknown"),
        "pod": os.getenv("HOSTNAME", "unknown")
    }

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/info")
def info():
    return {
        "app_env": os.getenv("APP_ENV", "not set"),
        "log_level": os.getenv("LOG_LEVEL", "not set"),
        "version": os.getenv("APP_VERSION", "1.0.0")
    }
```

**`requirements.txt`** (production dependencies only):

```
fastapi==0.111.0
uvicorn==0.29.0
```

**`requirements-dev.txt`** (local development extras):

```
fastapi==0.111.0
uvicorn==0.29.0
httpx==0.27.0
pytest==8.2.0
pytest-asyncio==0.23.6
```

**`Dockerfile`:**

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# Copy and install dependencies first (layer caching — only re-runs if requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

EXPOSE 8000

# Run as non-root user for security
RUN adduser --disabled-password --gecos '' appuser
USER appuser

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**`docker-compose.yml`** (for local testing only — not used in Kubernetes):

```yaml
services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - APP_VERSION=1.0.0
      - APP_ENV=local
      - LOG_LEVEL=debug
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s
```

**`tests/test_api.py`:**

```python
import pytest
from httpx import AsyncClient, ASGITransport
from main import app

@pytest.mark.asyncio
async def test_root():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "version" in data
    assert "env" in data
    assert "pod" in data

@pytest.mark.asyncio
async def test_health():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

@pytest.mark.asyncio
async def test_info():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/info")
    assert response.status_code == 200
    data = response.json()
    assert "app_env" in data
    assert "log_level" in data
```

---

### 4.4 Step 1 — Run and Validate Locally (Raw Python)

Always validate the app runs correctly in plain Python before touching Docker.

```bash
cd ~/k8s-demo-api

# Create and activate a virtual environment
python3.12 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements-dev.txt

# Verify installed packages
pip list

# Run the app locally
APP_VERSION=1.0.0 APP_ENV=local uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Open a second terminal and validate each endpoint:

```bash
# Test root endpoint
curl -s http://localhost:8000/ | python3 -m json.tool
# Expected:
# {
#     "message": "Hello from Kubernetes!",
#     "version": "1.0.0",
#     "env": "local",
#     "pod": "<your-hostname>"
# }

# Test health endpoint
curl -s http://localhost:8000/health | python3 -m json.tool
# Expected: {"status": "ok"}

# Test info endpoint
curl -s http://localhost:8000/info | python3 -m json.tool
# Expected:
# {
#     "app_env": "local",
#     "log_level": "not set",
#     "version": "1.0.0"
# }

# View the auto-generated API docs (open in browser)
curl -s http://localhost:8000/docs
# Or open http://localhost:8000/docs in your browser — FastAPI generates this automatically
```

Stop the server with `Ctrl+C` once validated.

---

### 4.5 Step 2 — Run Unit Tests

```bash
cd ~/k8s-demo-api
source venv/bin/activate

# Run all tests with verbose output
pytest tests/ -v

# Expected output:
# tests/test_api.py::test_root PASSED
# tests/test_api.py::test_health PASSED
# tests/test_api.py::test_info PASSED
# 3 passed in 0.XXs
```

If any test fails, fix the issue in `main.py` before proceeding. Do not move forward with a failing test suite.

---

### 4.6 Step 3 — Build and Validate the Docker Image

```bash
cd ~/k8s-demo-api

# Build the image
docker build -t yourusername/k8s-demo-api:1.0.0 .

# Verify the image was created
docker images | grep k8s-demo-api
# Should show:
# yourusername/k8s-demo-api   1.0.0   <id>   <seconds ago>   <size>

# Inspect the image layers (useful for understanding build caching)
docker history yourusername/k8s-demo-api:1.0.0
```

---

### 4.7 Step 4 — Run and Validate the Container Locally

This step confirms the app behaves correctly inside a container before pushing to Docker Hub. Environment variables here mirror what Kubernetes will inject.

```bash
# Run the container, passing env vars the same way Kubernetes will
docker run -d \
  --name k8s-demo-api-test \
  -p 8000:8000 \
  -e APP_VERSION=1.0.0 \
  -e APP_ENV=local \
  -e LOG_LEVEL=debug \
  yourusername/k8s-demo-api:1.0.0

# Verify the container is running
docker ps
# Should show k8s-demo-api-test with status 'Up'

# Check container logs (look for uvicorn startup message)
docker logs k8s-demo-api-test
# Expected: INFO:     Application startup complete.

# Validate all endpoints
curl -s http://localhost:8000/ | python3 -m json.tool
curl -s http://localhost:8000/health | python3 -m json.tool
curl -s http://localhost:8000/info | python3 -m json.tool

# Verify the healthcheck passes
docker inspect k8s-demo-api-test --format='{{.State.Health.Status}}'
# Expected: healthy  (may take ~15 seconds to show 'healthy' on first run)

# Check healthcheck history
docker inspect k8s-demo-api-test --format='{{json .State.Health}}' | python3 -m json.tool
```

Test that env vars are correctly injected:

```bash
# The /info endpoint should show your env vars
curl -s http://localhost:8000/info | python3 -m json.tool
# Expected:
# {
#     "app_env": "local",
#     "log_level": "debug",
#     "version": "1.0.0"
# }

# Exec into the running container to inspect manually
docker exec -it k8s-demo-api-test /bin/sh
  # Inside container:
  env | grep -E "APP|LOG"       # Verify env vars
  ps aux                         # Verify uvicorn process
  exit
```

Clean up the test container:

```bash
docker stop k8s-demo-api-test
docker rm k8s-demo-api-test
```

---

### 4.8 Step 5 — Validate with Docker Compose

Docker Compose lets you test the full container stack locally with a single command. It also validates your `docker-compose.yml` syntax.

```bash
cd ~/k8s-demo-api

# Start the stack
docker compose up -d

# Verify all services are healthy
docker compose ps
# Expected: api  running (healthy)

# View logs
docker compose logs -f api

# Run the same endpoint tests
curl -s http://localhost:8000/ | python3 -m json.tool
curl -s http://localhost:8000/health | python3 -m json.tool
curl -s http://localhost:8000/info | python3 -m json.tool

# Tear down
docker compose down
```

**✅ Checkpoint:** If all three steps above pass (raw Python, container, Compose), the application is validated and ready to push.

---

### 4.9 Step 6 — Tag and Push to Docker Hub

```bash
# Log in to Docker Hub
docker login
# Enter your Docker Hub username and password/token when prompted

# Tag for latest
docker tag yourusername/k8s-demo-api:1.0.0 yourusername/k8s-demo-api:latest

# Push both tags
docker push yourusername/k8s-demo-api:1.0.0
docker push yourusername/k8s-demo-api:latest

# Verify the push succeeded — pull it back to confirm
docker pull yourusername/k8s-demo-api:1.0.0
# Should say "Status: Image is up to date" or re-download and succeed
```

Verify on Docker Hub: open `https://hub.docker.com/r/yourusername/k8s-demo-api` in a browser and confirm the `1.0.0` and `latest` tags are listed.

---

### 4.10 Deploy Your Own Image to Kubernetes

Create `my-api-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
  namespace: apps
  labels:
    app: my-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    metadata:
      labels:
        app: my-api
    spec:
      containers:
      - name: api
        image: yourusername/k8s-demo-api:1.0.0   # <-- your image
        ports:
        - containerPort: 8000
        env:
        - name: APP_VERSION
          value: "1.0.0"
        - name: APP_ENV
          valueFrom:
            configMapKeyRef:
              name: demo-config
              key: APP_ENV
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 15
          periodSeconds: 20
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: my-api
---
apiVersion: v1
kind: Service
metadata:
  name: my-api-svc
  namespace: apps
spec:
  type: LoadBalancer
  selector:
    app: my-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8000
```

```bash
kubectl apply -f my-api-deployment.yaml
kubectl get svc -n apps  # Note the EXTERNAL-IP for my-api-svc
curl http://<EXTERNAL-IP>/
```

---

### 4.11 Manual Rolling Update (New Version)

Simulate a code change — add a new field to the root response in `main.py`:

```python
@app.get("/")
def root():
    return {
        "message": "Hello from Kubernetes!",
        "version": os.getenv("APP_VERSION", "2.0.0"),
        "env": os.getenv("APP_ENV", "unknown"),
        "pod": os.getenv("HOSTNAME", "unknown"),
        "updated": True                            # <-- new field in v2
    }
```

**Validate locally before building:**

```bash
cd ~/k8s-demo-api
source venv/bin/activate

# Run tests to confirm the change doesn't break anything
pytest tests/ -v
# All 3 tests should still pass

# Quick local sanity check
APP_VERSION=2.0.0 APP_ENV=local uvicorn main:app --port 8000 &
sleep 2
curl -s http://localhost:8000/ | python3 -m json.tool
# Verify "updated": true appears in response
kill %1   # Stop the background server
```

**Build, validate container, then push:**

```bash
# Build new version
docker build -t yourusername/k8s-demo-api:2.0.0 .

# Quick container validation before pushing
docker run -d --name api-v2-test -p 8001:8000 \
  -e APP_VERSION=2.0.0 -e APP_ENV=local \
  yourusername/k8s-demo-api:2.0.0

sleep 3
curl -s http://localhost:8001/ | python3 -m json.tool
# Confirm "updated": true is present and version is "2.0.0"

docker stop api-v2-test && docker rm api-v2-test

# Push to Docker Hub
docker push yourusername/k8s-demo-api:2.0.0

**Deploy the update to Kubernetes:**

```bash
# Update the deployment image (imperative approach)
kubectl set image deployment/my-api \
  api=yourusername/k8s-demo-api:2.0.0 \
  -n apps

# Watch the rolling update happen — old pods terminate, new ones start
kubectl rollout status deployment/my-api -n apps

# Verify new version is running
curl http://<EXTERNAL-IP>/ | python3 -m json.tool
# Should show "version": "2.0.0" and "updated": true
```

---

### 4.12 Rollback

```bash
# View rollout history
kubectl rollout history deployment/my-api -n apps

# Rollback to previous version
kubectl rollout undo deployment/my-api -n apps

# Rollback to specific revision
kubectl rollout undo deployment/my-api -n apps --to-revision=1

# Verify
kubectl rollout status deployment/my-api -n apps
curl http://<EXTERNAL-IP>/ | python3 -m json.tool
# Should show version "1.0.0" again and no "updated" field
```

---

### 4.13 Key Manual Deployment Commands Cheatsheet

```bash
# Apply / update from YAML
kubectl apply -f deployment.yaml

# Scale up/down replicas
kubectl scale deployment my-api --replicas=3 -n apps

# Force a restart (without changing image)
kubectl rollout restart deployment/my-api -n apps

# Describe pod (useful for debugging)
kubectl describe pod <pod-name> -n apps

# View logs
kubectl logs -n apps -l app=my-api -f --tail=50

# Exec into a container
kubectl exec -n apps -it <pod-name> -- /bin/bash

# Delete and recreate
kubectl delete -f deployment.yaml
kubectl apply -f deployment.yaml

# Get events (helpful when pods won't start)
kubectl get events -n apps --sort-by='.lastTimestamp'
```

---

## Block 5 — Automated Deployment with GitHub Actions (~1 hr)

### 5.1 Architecture Overview

```
git push → GitHub Actions → docker build → docker push → kubectl set image → rolling update
```

The pipeline will:
1. Trigger on push to `main`
2. Build and tag the Docker image with the Git SHA
3. Push to Docker Hub
4. Connect to your cluster via kubeconfig stored as a GitHub Secret
5. Perform a rolling update

---

### 5.2 Prerequisites

**Step 1:** Push your project to GitHub:

```bash
cd ~/k8s-demo-api
git init
git add .
git commit -m "Initial commit"
gh repo create k8s-demo-api --public --source=. --push
# Or: git remote add origin https://github.com/yourusername/k8s-demo-api.git && git push -u origin main
```

**Step 2:** Get your kubeconfig for GitHub Actions. On your desktop:

```bash
# Print kubeconfig — you'll store this as a GitHub Secret
cat ~/.kube/config
```

> ⚠️ **Security note:** This kubeconfig grants full admin access. For production, create a restricted ServiceAccount. For home lab, this is acceptable.

---

### 5.3 Store GitHub Secrets

In your GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

| Secret Name | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token (not password) — create at hub.docker.com/settings/security |
| `KUBE_CONFIG` | Full contents of `~/.kube/config` |

---

### 5.4 Make Your Cluster Accessible from GitHub Actions

GitHub Actions runners are external to your network. You need to expose the Kubernetes API server (port 6443).

**Option A — Cloudflared Tunnel (Recommended for your setup):**

```bash
# On desktop, install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# Authenticate
cloudflared tunnel login

# Create a tunnel for the API server
cloudflared tunnel create k8s-api
cloudflared tunnel route dns k8s-api k8s.yourdomain.com

# Create config
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml <<EOF
tunnel: <YOUR-TUNNEL-ID>
credentials-file: /home/$USER/.cloudflared/<YOUR-TUNNEL-ID>.json
ingress:
  - hostname: k8s.yourdomain.com
    service: https://localhost:6443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

# Run as a service
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

Update your kubeconfig's `server` field to `https://k8s.yourdomain.com` before storing it in GitHub Secrets.

**Option B — Port Forward on Router:**
Forward external TCP port 6443 to your desktop's IP:6443. Use a DDNS service for a stable hostname.

---

### 5.5 GitHub Actions Workflow

Create `.github/workflows/deploy.yml` in your repo:

```yaml
name: Build and Deploy to Kubernetes

on:
  push:
    branches:
      - main
  workflow_dispatch:                  # Allow manual trigger from GitHub UI

env:
  IMAGE_NAME: ${{ secrets.DOCKERHUB_USERNAME }}/k8s-demo-api

jobs:
  test:
    name: Run Unit Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        run: pip install -r requirements-dev.txt

      - name: Run tests
        run: pytest tests/ -v

  build-and-push:
    name: Build & Push Docker Image
    runs-on: ubuntu-latest
    needs: test                       # Only runs if tests pass
    outputs:
      image-tag: ${{ steps.meta.outputs.version }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=,format=short
            type=ref,event=branch
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    name: Deploy to Kubernetes
    runs-on: ubuntu-latest
    needs: build-and-push
    environment: production

    steps:
      - name: Set up kubectl
        uses: azure/setup-kubectl@v3
        with:
          version: 'v1.32.0'

      - name: Configure kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBE_CONFIG }}" > ~/.kube/config
          chmod 600 ~/.kube/config

      - name: Verify cluster connection
        run: kubectl get nodes

      - name: Deploy new image
        run: |
          IMAGE_TAG=$(echo "${{ github.sha }}" | cut -c1-7)
          kubectl set image deployment/my-api \
            api=${{ env.IMAGE_NAME }}:${IMAGE_TAG} \
            -n apps

      - name: Wait for rollout to complete
        run: |
          kubectl rollout status deployment/my-api -n apps --timeout=300s

      - name: Verify deployment
        run: |
          kubectl get pods -n apps -l app=my-api
          echo "Deployment successful ✅"

      - name: Rollback on failure
        if: failure()
        run: |
          echo "Deployment failed — rolling back..."
          kubectl rollout undo deployment/my-api -n apps
          kubectl rollout status deployment/my-api -n apps
```

Commit and push:

```bash
git add .github/workflows/deploy.yml
git commit -m "Add CI/CD pipeline"
git push
```

Go to GitHub → Actions tab and watch the pipeline run automatically.

---

### 5.6 Using Environments for Approval Gates

For production deployments, add a manual approval step:

1. In GitHub repo: **Settings → Environments → New environment → Name: `production`**
2. Enable **Required reviewers** and add yourself
3. The `deploy` job with `environment: production` will pause and wait for your approval

---

## Block 6 — Validation, Troubleshooting & Next Steps (~30 min)

### 6.1 Validate Your Cluster is Healthy

```bash
# All nodes Ready
kubectl get nodes

# All system pods running
kubectl get pods -n kube-system

# Your application pods running across both nodes
kubectl get pods -n apps -o wide

# Services have external IPs
kubectl get svc -n apps

# End-to-end test
curl http://<EXTERNAL-IP>/
curl http://<EXTERNAL-IP>/health
```

---

### 6.2 Common Troubleshooting Commands

```bash
# Pod stuck in Pending
kubectl describe pod <pod-name> -n apps
# Look for: Insufficient CPU/memory, scheduling constraints, PVC pending

# Pod in CrashLoopBackOff
kubectl logs <pod-name> -n apps
kubectl logs <pod-name> -n apps --previous   # logs from previous crash

# Pod in ImagePullBackOff
kubectl describe pod <pod-name> -n apps
# Check: image name typo, private registry auth, network access

# Node not Ready
kubectl describe node <node-name>
# Check: kubelet logs on that node
sudo journalctl -u kubelet -n 50

# Service not getting external IP
kubectl describe svc <svc-name> -n apps
# Check: MetalLB is running, IP pool is configured correctly

# General cluster events
kubectl get events -n apps --sort-by='.lastTimestamp'
```

---

### 6.3 Useful Aliases (Add to ~/.bashrc)

```bash
# Add to ~/.bashrc on desktop
alias k='kubectl'
alias kga='kubectl get all'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias kns='kubectl config set-context --current --namespace'

# Quick namespace switch
kns apps   # Now all kubectl commands default to 'apps' namespace
```

---

### 6.4 What You've Built Today

```
┌─────────────────────────────────────────────────────────┐
│                   Your Home Lab Cluster                  │
│                                                         │
│  GitHub Actions ──push──► Docker Hub                    │
│         │                     │                         │
│         └──kubectl set image───┤                        │
│                                ▼                        │
│         ┌──────────────────────────────────┐            │
│         │         MetalLB                  │            │
│         │    192.168.1.200 (LoadBalancer)  │            │
│         └──────────┬───────────────────────┘            │
│                    │ round-robin                         │
│         ┌──────────┴───────────┐                        │
│         ▼                      ▼                        │
│   ┌──────────────┐      ┌──────────────┐               │
│   │   Desktop    │      │    Laptop    │               │
│   │ (Control     │      │  (Worker)    │               │
│   │   Plane)     │      │              │               │
│   │  Pod 1 ✅    │      │  Pod 2 ✅    │               │
│   └──────────────┘      └──────────────┘               │
│                                                         │
│  ConfigMaps + Secrets injected as env vars              │
│  Rolling updates with automatic rollback                │
└─────────────────────────────────────────────────────────┘
```

---

### 6.5 Next Steps for Your Specific Services

#### InfluxDB

```bash
# Add InfluxDB Helm chart
helm repo add influxdata https://helm.influxdata.com/
helm repo update
helm install influxdb influxdata/influxdb2 \
  --namespace apps \
  --set adminUser.password=<yourpassword> \
  --set persistence.enabled=true \
  --set persistence.size=10Gi
```

#### Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace apps \
  --set adminPassword=<yourpassword> \
  --set service.type=LoadBalancer
```

#### Cloudflared Tunnel for Services

```bash
# Create a tunnel config that routes to your Services' cluster IPs
# Add ingress rules per service in your cloudflared config
```

#### Persistent Storage

For stateful services (InfluxDB, Grafana), you'll need a `PersistentVolumeClaim`. For a 2-node home lab, use `local-path-provisioner`:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

### 6.6 Helm — Package Manager for Kubernetes

Helm is to Kubernetes what `apt` is to Ubuntu. Install it:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

Most production-grade services (InfluxDB, Grafana, cert-manager) have Helm charts that handle all the YAML complexity for you.

---

### 6.7 Ingress Controller (Optional Enhancement)

Instead of one LoadBalancer IP per service, use a single IP with path/host-based routing:

```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

# Example Ingress resource
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: home-lab-ingress
  namespace: apps
spec:
  ingressClassName: nginx
  rules:
  - host: api.home.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-api-svc
            port:
              number: 80
  - host: grafana.home.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
EOF
```

---

## Quick Reference Card

| Task | Command |
|---|---|
| Get all resources in namespace | `kubectl get all -n apps` |
| Watch pods | `kubectl get pods -n apps -w` |
| Apply YAML | `kubectl apply -f file.yaml` |
| Delete resource | `kubectl delete -f file.yaml` |
| Scale deployment | `kubectl scale deploy/my-api --replicas=3 -n apps` |
| Update image | `kubectl set image deploy/my-api api=image:tag -n apps` |
| Rollback | `kubectl rollout undo deploy/my-api -n apps` |
| Exec into pod | `kubectl exec -it <pod> -n apps -- bash` |
| View logs | `kubectl logs -l app=my-api -n apps -f` |
| Describe pod | `kubectl describe pod <pod> -n apps` |
| Get events | `kubectl get events -n apps --sort-by=.lastTimestamp` |
| Port forward | `kubectl port-forward svc/my-api-svc 8080:80 -n apps` |
| View secrets | `kubectl get secret <name> -n apps -o jsonpath='{.data.KEY}' \| base64 -d` |

---

*Generated for Joshua's Home Lab — Ubuntu 26.04 Desktop (Control Plane) + Ubuntu 26.06 Laptop (Worker) | Kubernetes v1.32 | MetalLB v0.14 | Flannel CNI*
