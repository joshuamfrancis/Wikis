# EKS Learning Plan — Native Ubuntu 26.04 Host, Single-Host Local Cluster

**Revision:** targets a native Ubuntu 26.04 LTS ("Resolute Raccoon") workstation.
No WSL, no Git Bash, no second machine. One host runs the control plane and the
worker nodes for all local work; AWS runs the control plane only during paid EKS
sessions.

**Model:** the EKS cluster is cattle. It exists only while you are actively typing
into it. Idle cost target is **$0.00/day**.

**Budget:** ~$0.50 per 3-hour session, **~$6–10 over the full eight weeks**.

---

## Host requirements

**Target host: Ubuntu 26.04 LTS Desktop, 24 GB RAM.** Desktop edition, because
you need VS Code, a browser for the AWS console and Grafana, and `localhost:8080`
for the kind Ingress mapping on the same machine.

| | Minimum | This host |
|---|---|---|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | **24 GB** |
| Disk | 40 GB free | 100 GB free (SSD) |

24 GB removes memory as a constraint. GNOME 50 on Wayland holds ~2.5 GB, leaving
~21 GB — enough for a three-node kind cluster running kube-prometheus-stack
(~3 GB), ArgoCD (~1 GB), and your own workloads at the same time, with headroom
for a second kind cluster.

**Disk is now the binding constraint, not RAM.** Node images, Prometheus volumes,
and your own builds accumulate quickly. Check `docker system df` at the end of
each module and run `docker system prune -a --volumes` between phases. If `/` has
less than 100 GB free, move Docker's data root to a larger volume via
`/etc/docker/daemon.json` (`{"data-root": "/path/to/docker"}`) before you start.

Confirm before starting:

```bash
lsb_release -a          # Ubuntu 26.04 LTS
uname -r                # Linux 7.x
nproc && free -g && df -h /
```

---

## Phase 0 — Host setup (one-time, free)

### Step 0.1 — Base packages

<cite index="11-1">26.04 ships systemd 259 with mandatory cgroup v2 and Rust-based core
utilities</cite>, so a couple of long-standing assumptions have changed. Nothing below
depends on them, but see Step 0.6 for the edge cases.

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip jq git make gnupg ca-certificates \
                    python3-venv python3-pip apt-transport-https
```

### Step 0.2 — Docker CE (not the snap)

**Do not use the snap package.** Snap confinement breaks kind's node containers
with opaque mount errors. Check first and remove it if present:

```bash
snap list docker 2>/dev/null && sudo snap remove docker
```

Install Docker CE from Docker's own repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker            # or log out and back in
```

If `resolute` is not yet carried in Docker's repo, substitute the previous LTS
codename (`noble`) in the `deb` line — the packages are compatible.

Verify — this must succeed **without sudo**:

```bash
docker run --rm hello-world
docker info | grep -E "Cgroup Version|Storage Driver|Server Version"
```

Expect `Cgroup Version: 2` and `Storage Driver: overlay2`. If cgroup version
reads 1, something has overridden the kernel cmdline; fix it before continuing.

### Step 0.3 — Kernel tuning for a single-host cluster

Running control plane and workers on one machine multiplies the file-watch and
process load. Without this, kind clusters fail at node three or when Prometheus
starts.

```bash
sudo tee /etc/sysctl.d/99-k8s-lab.conf > /dev/null <<'EOF'
fs.inotify.max_user_watches   = 1048576
fs.inotify.max_user_instances = 8192
fs.file-max                   = 2097152
vm.max_map_count              = 262144
net.ipv4.ip_forward           = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo modprobe br_netfilter
echo br_netfilter | sudo tee /etc/modules-load.d/k8s.conf
sudo sysctl --system
```

Also raise the per-user process limit, since three node containers plus their
kubelets and pods add up:

```bash
sudo tee /etc/security/limits.d/99-k8s-lab.conf > /dev/null <<'EOF'
*  soft  nofile  1048576
*  hard  nofile  1048576
EOF
```

Disable swap for anything running kubelet directly (kubeadm path in Module 03b).
kind does not require this, but it removes a class of confusing behaviour:

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Step 0.4 — Tooling

All static binaries, all distro-agnostic:

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# eksctl
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
  | tar xz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kind — pinned via GitHub releases, not the /dl/latest/ path
curl -Lo kind https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

# k9s
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz \
  | tar xz -C /tmp && sudo mv /tmp/k9s /usr/local/bin

# kubectx / kubens
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens  /usr/local/bin/kubens

for t in aws kubectl eksctl helm kind k9s; do
  printf '%-10s' "$t:"; $t version 2>&1 | head -1
done
```

Shell completion and a context indicator in your prompt — worth the five minutes,
because the single most expensive mistake in this plan is running `kubectl delete`
against EKS when you meant kind:

```bash
cat >> ~/.bashrc <<'EOF'
source <(kubectl completion bash)
source <(eksctl completion bash)
source <(helm completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
export AWS_PROFILE=eks-lab
PS1='\[\e[36m\][$(kubectl config current-context 2>/dev/null || echo none)]\[\e[0m\] '"$PS1"
EOF
source ~/.bashrc
```

VS Code: install the `.deb` from Microsoft's repo rather than the snap — the snap
build has had file-watcher and integrated-terminal quirks with Docker group
membership. Extensions: Kubernetes, YAML (Red Hat), AWS Toolkit, Docker, Python.

### Step 0.5 — AWS account

1. Dedicated IAM user or Identity Center user named `eks-lab`. Never root.
2. `aws configure --profile eks-lab` → region `us-east-1`, output `json`.
3. `aws sts get-caller-identity` — confirm the account ID is what you expect.
4. **Guardrails, before your first cluster:**
   - Budgets → monthly cost budget, $15, alerts at 50/80/100% actual + 100% forecast
   - Cost Anomaly Detection → AWS services monitor, daily alerts
   - Cost Explorer → enable, and activate `Project` as a cost allocation tag

### Step 0.6 — Ubuntu 26.04 specifics to know about

- **Rust coreutils.** <cite index="11-1">26.04 uses memory-safe Rust-based core
  utilities.</cite> Behaviour is near-identical, but if `date -d "<iso8601>" +%s` in the
  reaper script misparses, replace that line with
  `python3 -c "import datetime,sys;print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))" "$CREATED"`.
- **PEP 668.** `pip install boto3` on the host is refused. Use a venv for all
  Python module work: `python3 -m venv .venv && source .venv/bin/activate`.
  Inside container images it is unaffected.
- **AppArmor unprivileged user namespace restrictions.** These do not affect
  rootful Docker (our setup). If you later experiment with rootless Docker or
  Podman, expect to relax
  `kernel.apparmor_restrict_unprivileged_userns`.
- **Snap permission prompting is on by default** in 26.04. If you install any
  lab tooling as a snap, expect permission dialogs mid-session. Prefer `.deb`
  and raw binaries throughout.

### Step 0.7 — Repo

```bash
mkdir -p ~/eks-lab && cd ~/eks-lab && git init
mkdir -p local/{kind,kubeadm} scripts modules .github/workflows
printf 'kubeconfig*\n*.pem\n.env\n.venv/\n*.tfstate*\n' > .gitignore
```

```
eks-lab/
├── local/kind/cluster.yaml     # single-host multi-node local cluster
├── cluster.yaml                # eksctl definition
├── scripts/{up.sh,down.sh,verify-clean.sh,local-up.sh,local-down.sh}
├── modules/01-basics … 10-private-networking/
└── .github/workflows/{build-push.yml,reaper.yml}
```

---

## Phase 1 — Single-host local Kubernetes (Weeks 1–2, $0.00)

One physical host, control plane and workers together. Two ways to do this; use
kind as your daily driver and do the kubeadm variant once for understanding.

### Option A (primary) — kind: control plane + workers as containers on the host

`local/kind/cluster.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: lab
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
networking:
  apiServerAddress: "127.0.0.1"
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/16"
```

`scripts/local-up.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
kind create cluster --config "$(dirname "$0")/../local/kind/cluster.yaml"
kubectl cluster-info --context kind-lab
kubectl get nodes -o wide
# ingress-nginx, reachable on http://localhost:8080
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
```

`scripts/local-down.sh`: `kind delete cluster --name lab`

The `extraPortMappings` block is what makes a single-host cluster genuinely
useful — Ingress resources become reachable at `http://localhost:8080` with no
tunnelling, which is the closest local analogue to the ALB you will meet in
Module 06.

At 24 GB you can run two named clusters side by side — copy the config to
`local/kind/cluster-staging.yaml` with `name: staging` and different `hostPort`
values (8081/8443). Module 09 uses this for ArgoCD multi-cluster registration
without paying for a second EKS control plane.

### Option B (once, for understanding) — kubeadm single-node

Run this once so you have seen the control plane as processes on your own machine
rather than as an abstraction:

```bash
# containerd + kubeadm/kubelet from pkgs.k8s.io, then:
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# make the control-plane node schedulable — this is the "single host" part
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

Inspect `/etc/kubernetes/manifests/` and `crictl ps` to see apiserver, etcd,
scheduler, and controller-manager as static pods. Then `sudo kubeadm reset -f`
and go back to kind. **Do not** leave kubeadm and kind running simultaneously —
they will fight over ports and iptables rules.

### Local modules (free)

- **01 — Core objects.** Pod, Deployment, Service, ConfigMap, Secret, written by
  hand. `describe`, `logs`, `exec`, `port-forward`. Break things deliberately:
  bad image tag, wrong containerPort, missing ConfigMap key — diagnose each from
  `describe` alone. Deliverable: a Python Flask app with a Dockerfile, running in
  kind. Load images with `kind load docker-image` to skip the registry round trip.
- **02 — Config, health, resources.** Probes, requests/limits, watch an
  OOMKilled pod, namespaces, RBAC with `kubectl auth can-i --as=...`.
- **03 — Ingress and Helm.** Expose the Flask app via Ingress on
  `localhost:8080`. Then `helm create`, template the image tag and replicas,
  `helm upgrade`, `helm rollback`.
- **03b — kubeadm single node** (Option B above), once.

**Exit criteria:** deploy, expose, debug, and roll back without looking anything
up. Then `./scripts/local-down.sh` and move to AWS.

---

## Phase 2 — EKS (unchanged from the base plan)

The EKS control plane is AWS-managed, so nothing here is affected by the host OS.
Your workstation only needs `eksctl`, `kubectl`, `helm`, and credentials.

Cluster definition, `up.sh`, `down.sh`, `verify-clean.sh`, and the reaper workflow
are as in the original plan. The essentials:

- `nat.gateway: Disable` and `privateNetworking: false` — no NAT Gateway, which
  otherwise bills ~$32/month whether or not a cluster exists
- Spot `t3.medium`/`t3a.medium`, 2 nodes, `volumeType: gp3`
- `iam.withOIDC: true` from day one, for IRSA
- `cloudWatch.clusterLogging.enableTypes: []`
- Version pinned to a current release; never drift into extended support at
  $0.60/hr
- `down.sh` deletes Ingresses and LoadBalancer Services **first**, then PVCs,
  waits 60s, then the cluster
- `verify-clean.sh` after every session: no clusters, no ELBs, no available EBS
  volumes, no unassociated EIPs, no NAT gateways, no running instances, no
  `eksctl-*` CloudFormation stacks

### Module sequence

| # | Focus | Where |
|---|---|---|
| 04 | Cluster lifecycle, kubeconfig, VPC inspection, timed up/down | EKS |
| 05 | EKS access entries + **IRSA** — Python/boto3 pod reads S3, no keys | EKS |
| 06 | **AWS Load Balancer Controller** — NLB Service, then ALB Ingress | EKS |
| 07 | **EBS CSI** + StatefulSet Postgres; PVC reclaim behaviour | EKS |
| 08 | **Karpenter**, HPA, PodDisruptionBudget, spot interruption | EKS |
| 09 | GitHub Actions → Docker Hub → **ArgoCD** auto-sync, self-heal, Kustomize overlays | **kind first**, then one short EKS session for ALB-fronted ArgoCD |
| 10 | Prometheus/Grafana, network policies, `trivy k8s` | **kind** |
| 10b | EKS audit logging, then rebuild with private subnets + NAT and compare cost | EKS |

Rehearse in kind first wherever possible. Helm chart authoring, manifest
debugging, and RBAC experiments cost nothing locally and cost $0.10/hr on EKS.

**With 24 GB, Modules 09 and 10 move mostly local.** ArgoCD reconciliation,
Prometheus scraping, Grafana dashboards, and network policies are plain
Kubernetes — none of it is EKS-specific. Build the full GitOps loop against
`kind-lab` and `kind-staging`, then spend one 90-minute EKS session proving it
works against a real cluster with an ALB in front of ArgoCD.

The genuinely un-fakeable modules are 05 (IRSA), 06 (ALB controller), 07 (EBS
CSI), and 08 (Karpenter node provisioning). Those stay paid. Everything else
should be working locally before you `up.sh`.

---

## Session runbook

**Before**
1. `aws sts get-caller-identity` — right account?
2. `./scripts/verify-clean.sh` — anything left from last time?
3. Phone timer: session length + 30 min.
4. Manifests already written. Know which module you are doing.

**During**
5. `./scripts/up.sh` (~15 min)
6. Work the module; commit manifests as you go
7. Notes in `modules/NN/NOTES.md` — what broke, what fixed it

**After**
8. `./scripts/down.sh`
9. `./scripts/verify-clean.sh` — every section empty
10. `git push`
11. Next morning: Cost Explorer filtered to `Project=eks-lab`, confirm the number

Check your prompt's context indicator before every destructive command. On a
single host you will have `kind-lab` and `eks-lab` contexts side by side, and
they look similar at 11pm.

---

## Schedule

| Week | Work | EKS sessions | Cost |
|---|---|---|---|
| 1 | Phase 0 host setup + Module 01 | 0 | $0.00 |
| 2 | Modules 02, 03, 03b | 0 | $0.00 |
| 3 | Modules 04 + 05 | 2 | ~$0.60 |
| 4 | Module 06 | 1–2 | ~$0.70 |
| 5 | Module 07 | 1–2 | ~$0.60 |
| 6 | Module 08 | 2 | ~$1.00 |
| 7 | Module 09 — build in kind, verify on EKS | 1 | ~$0.50 |
| 8 | Module 10 in kind + Module 10b on EKS | 1 | ~$0.60 |
| | | **8–10 total** | **≈ $4–6** |

---

## Failure modes on this setup

- **kind node "not ready", or pods stuck ContainerCreating** — almost always
  inotify or file-descriptor limits. Re-check Step 0.3 and confirm with
  `cat /proc/sys/fs/inotify/max_user_instances`.
- **`docker: permission denied`** — group membership not picked up. Log out fully;
  `newgrp docker` only affects the current shell.
- **kind cluster vanishes after reboot** — expected. Node containers do not
  auto-restart cleanly; recreate with `local-up.sh`. Keep all state in Git.
- **Port 8080 already in use** — something else on the host has it. Change
  `hostPort` in the kind config rather than fighting it.
- **`no space left on device` mid-module** — the likely failure at 24 GB RAM, since
  disk fills long before memory does. `docker system df`, then
  `docker system prune -a --volumes`. Deleting a kind cluster does not reclaim
  its images.
- **Two kind clusters fighting over ports** — each needs distinct `hostPort`
  values and a distinct `name:` in its config.
- **`eksctl delete cluster` hangs** — stuck ALB or attached ENI. Read the
  CloudFormation stack events for the blocking resource, delete it in the
  console, retry.
- **IRSA AccessDenied** — the role trust policy `sub` condition must match
  `system:serviceaccount:<namespace>:<name>` exactly.

---

## Definition of done

From a fresh `git clone` on this host and an empty AWS account: an application
exposed through an ALB, backed by EBS persistent storage, deployed by ArgoCD from
Git, with pods authenticating to S3 via IRSA — in under 30 minutes, without
consulting documentation. Then tear it down and watch the bill return to zero.
