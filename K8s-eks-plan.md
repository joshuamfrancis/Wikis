# EKS Study Plan — 8 Weeks, Single Ubuntu Host

Companion to the *EKS Learning Plan* (host setup + module definitions). That document tells you **what to build**. This one tells you **when to study it, in what order, and how to know you actually learned it**.

Same constraints: one Ubuntu 26.04 host, 24 GB RAM, kind as the daily driver, EKS only while you are typing into it. Budget $6–10 total.

---

## 0. The study loop

Every topic in this plan goes through the same six steps. Do not skip step 3 — it is where the learning actually happens.

| # | Step | Time | Why |
|---|------|------|-----|
| 1 | **Read** the one canonical doc page for the object | 15–20 min | Spec first, blog posts never |
| 2 | **Write** the manifest by hand, no copy-paste, no `kubectl create --dry-run` | 20 min | Recall beats recognition |
| 3 | **Break** it deliberately (one mutation at a time) | 20 min | You will only ever debug in the wild |
| 4 | **Diagnose** from `describe` + `get events` alone — no Google, no scrollback | 10 min | Builds the failure-signature index |
| 5 | **Write up** in `modules/NN/NOTES.md`: symptom → cause → fix | 10 min | The artifact you re-read in week 8 |
| 6 | **Recall** at the start of the *next* session, from memory | 5 min | Spaced repetition |

**Rule:** if you copy-pasted a manifest, you have not studied it. Retype it.

---

## 1. Weekly cadence

Five sessions per week. Four are free and local, one is paid or a review block.

| Slot | Length | Type | Content |
|------|--------|------|---------|
| Mon | 60 min | Local | New concept, steps 1–2 |
| Tue | 60 min | Local | Break/fix drills, steps 3–5 |
| Wed | 90 min | Local | Build the module deliverable |
| Thu | 60 min | Local | Rehearse the EKS-specific parts in kind |
| Sat | 3 hr | **Paid EKS** or review | Full session runbook, or catch-up if no EKS this week |

Start every session with a 5-minute **recall drill** (Section 8) before touching a keyboard. End every session with `docker system df` and a NOTES.md entry.

Timer discipline: phone timer for session length **+ 30 minutes** on every paid session. When it fires, you run `down.sh` regardless of where you are. An unfinished module costs nothing; a forgotten NAT gateway costs $32.

---

## 2. Prerequisite check (do this before Week 1)

Do not start Module 01 until all of these are true. Fixing them mid-module is how weeks get lost.

```bash
lsb_release -a && uname -r          # Ubuntu 26.04, kernel 7.x
nproc && free -g && df -h /         # >=4 cores, >=8 GB, >=100 GB free
docker run --rm hello-world         # succeeds WITHOUT sudo
docker info | grep -E "Cgroup Version|Storage Driver"   # 2, overlay2
cat /proc/sys/fs/inotify/max_user_instances             # 8192
kind version && kubectl version --client && helm version --short
aws sts get-caller-identity --profile eks-lab           # expected account id
```

Plus, in the AWS console:
- [ ] Budget: $15/month, alerts at 50 / 80 / 100% actual and 100% forecast
- [ ] Cost Anomaly Detection enabled, daily alerts
- [ ] `Project` activated as a cost allocation tag
- [ ] No root access keys exist

**Knowledge prerequisites.** If any of these are shaky, spend Week 0 on them rather than discovering the gap in Module 05:
- Linux processes, namespaces, cgroups at a conceptual level
- Docker: images vs containers, layers, `ENTRYPOINT` vs `CMD`, bind mounts
- TCP/IP basics: ports, DNS resolution, what a reverse proxy does
- AWS: VPC, subnet, route table, security group, IAM role vs policy vs trust policy
- Git: branch, rebase, and what a `.gitignore` actually excludes

---

## 3. Phase 1 — Local Kubernetes (Weeks 1–2, $0.00)

### Week 1 — Host + core objects (Module 01)

**Goal:** you can produce a running, reachable Flask app in kind without reading anything.

| Day | Work |
|-----|------|
| Mon | Phase 0 steps 0.1–0.4. Install everything, verify each binary prints a version. Do **not** skip the kernel tuning in 0.3 — it is the cause of the most common failure mode. |
| Tue | Steps 0.5–0.7. AWS user, guardrails, repo scaffold, first commit. Add the context indicator to `PS1` and confirm it renders. |
| Wed | `local-up.sh`. Three nodes up. Then Module 01 part 1: Pod → Deployment → Service, each typed by hand. `describe`, `logs`, `exec`, `port-forward` on every one. |
| Thu | Module 01 part 2: ConfigMap and Secret, mounted both as env vars and as files. Understand why a mounted ConfigMap updates live and an env var does not. |
| Sat | Build the deliverable: Python Flask app, Dockerfile, `kind load docker-image`, Deployment + Service. Break/fix drills below. |

**Break/fix drills (Module 01)** — do each, diagnose from `describe` alone, record the signature:

1. Bad image tag → `ErrImagePull` / `ImagePullBackOff`
2. `containerPort` mismatched to the Service `targetPort` → connection refused, endpoints empty
3. Selector label typo → Service with zero endpoints, `kubectl get endpoints` is the tell
4. Referenced ConfigMap key that does not exist → `CreateContainerConfigError`
5. Image built locally but never `kind load`ed → pull failure on a private-looking name
6. Command that exits 0 immediately → `CrashLoopBackOff` with no error in logs

**Exit criteria:** from an empty namespace, deploy the Flask app and reach it via `port-forward` in under 5 minutes, no references.

---

### Week 2 — Config, health, Ingress, Helm, kubeadm (Modules 02, 03, 03b)

| Day | Work |
|-----|------|
| Mon | **Module 02a** — probes. Liveness, readiness, startup. Deliberately set a liveness probe that fails and watch the restart loop. Understand why a failing *readiness* probe removes the pod from endpoints but does not restart it. |
| Tue | **Module 02b** — resources. requests vs limits, QoS classes (Guaranteed / Burstable / BestEffort). Force an `OOMKilled` with a memory-hungry Python loop and a 64Mi limit. Then force a `Pending` pod by requesting more CPU than the node has. |
| Wed | **Module 02c** — namespaces and RBAC. Role, RoleBinding, ClusterRole, ServiceAccount. Drill `kubectl auth can-i --as=system:serviceaccount:dev:app get secrets -n prod` until the mental model is automatic. This is the direct precursor to IRSA in Module 05. |
| Thu | **Module 03** — Ingress. ingress-nginx is already installed by `local-up.sh`; expose Flask on `http://localhost:8080`. Path-based and host-based rules. Then a second app, and route between them. |
| Sat | **Module 03 Helm** — `helm create`, strip the boilerplate to nothing, rebuild it. Template image tag and replicas. `helm upgrade`, `helm rollback`, `helm template` to see the rendered output. Then **Module 03b**: kubeadm single node, once. |

**Module 03b is a one-sitting exercise, not a project.** `kubeadm init`, remove the control-plane taint, then look at exactly three things:

```bash
ls /etc/kubernetes/manifests/     # apiserver, etcd, scheduler, controller-manager
sudo crictl ps                    # the same four, as running containers
sudo crictl logs <apiserver-id> | tail -50
```

Then `sudo kubeadm reset -f` and go back to kind. The point is to have seen the control plane as processes once, so that "AWS manages the control plane" means something concrete when you pay for it in Week 3.

**Exit criteria for Phase 1 — all must be true before you spend a cent:**
- [ ] Deploy, expose via Ingress, and roll back a Helm release without looking anything up
- [ ] Diagnose all six Module 01 failure signatures from `describe` in under 60 seconds each
- [ ] Explain the difference between a liveness and readiness probe failure, out loud, correctly
- [ ] `kubectl auth can-i --as=...` is a reflex, not a lookup
- [ ] Everything is committed and pushed

---

## 4. Phase 2 — EKS (Weeks 3–8)

From here, every paid session follows the runbook. Non-negotiable.

**Before:** `aws sts get-caller-identity` → `./scripts/verify-clean.sh` → phone timer set → manifests already written and committed.
**During:** `./scripts/up.sh` (~15 min — do the recall drill while it provisions) → work the module → commit as you go.
**After:** `./scripts/down.sh` → `./scripts/verify-clean.sh` → `git push` → next morning, Cost Explorer filtered to `Project=eks-lab`.

**Check your prompt context indicator before every destructive command.** `kind-lab` and the EKS ARN look similar at 11pm and one of them costs money to rebuild.

---

### Week 3 — Cluster lifecycle + IRSA (Modules 04, 05) — 2 sessions, ~$0.60

| Day | Work |
|-----|------|
| Mon | Study `cluster.yaml` line by line. For each field, answer: what does this cost if I get it wrong? Focus on `nat.gateway: Disable`, `privateNetworking: false`, spot instances, `withOIDC: true`, empty `clusterLogging`. |
| Tue | Write `up.sh`, `down.sh`, `verify-clean.sh`. Dry-run the logic locally. `down.sh` must delete Ingresses and LoadBalancer Services **first**, then PVCs, wait 60s, then the cluster. |
| Wed | Study IRSA on paper. Draw the trust chain: OIDC provider → role trust policy → `sub` condition → ServiceAccount annotation → projected token → `AssumeRoleWithWebIdentity`. Write the boto3 S3 script and its Dockerfile; push to Docker Hub. |
| **Sat** | **PAID SESSION 1 (Module 04, ~90 min).** `up.sh`. Inspect the generated VPC in the console: subnets, route tables, security groups, the absence of a NAT gateway. `kubectl config view` — understand what `aws eks update-kubeconfig` actually wrote. Then a full `down.sh` + `verify-clean.sh` cycle. Time the up and the down; write both numbers in NOTES.md. |
| **Sun** | **PAID SESSION 2 (Module 05, ~90 min).** Access entries, then IRSA end to end. Pod reads S3 with zero static credentials. Then break it: change the `sub` condition to the wrong namespace and confirm you recognise the `AccessDenied`. |

**Study focus:** IRSA is the single most transferable thing in this plan. Also read up on **EKS Pod Identity** as the newer alternative and be able to state the tradeoff (Pod Identity is simpler to configure and does not need an OIDC provider per cluster; IRSA is what most existing code and docs assume). You do not need to implement both.

---

### Week 4 — Load balancing (Module 06) — 1–2 sessions, ~$0.70

| Day | Work |
|-----|------|
| Mon–Tue | Concepts, free. NLB vs ALB. Service type LoadBalancer vs Ingress. What the AWS Load Balancer Controller actually watches and what it creates. Target types `instance` vs `ip` — know why `ip` matters. |
| Wed | Write every annotation you will need, in kind, against ingress-nginx. The Ingress *shape* is identical; only the annotations differ. Rehearsing here means the paid session is pure execution. |
| Thu | IAM policy for the controller + its IRSA role. This is Module 05's lesson applied — write it from memory first, then check. |
| **Sat** | **PAID SESSION (~2 hr).** Install the controller via Helm. Service type LoadBalancer → NLB, verify. Then ALB Ingress with path routing to two services. Watch the ALB appear in the console. Then `down.sh` and confirm in `verify-clean.sh` that **no ELB survives** — this is the classic orphaned-resource bill. |

**Danger note:** deleting a cluster before deleting its Ingresses leaves the ALB running. It is only a few cents an hour, but it is a few cents an hour forever. This is what `down.sh` ordering is for.

---

### Week 5 — Storage (Module 07) — 1–2 sessions, ~$0.60

| Day | Work |
|-----|------|
| Mon | Volume taxonomy: emptyDir, hostPath, PV, PVC, StorageClass, dynamic provisioning. Reclaim policies `Delete` vs `Retain` and the cost consequence of each. |
| Tue | StatefulSet vs Deployment. `volumeClaimTemplates`, stable network identity, ordered rollout. Build a Postgres StatefulSet **in kind** with the local-path provisioner. |
| Wed | Data-persistence drill in kind: write rows, `kubectl delete pod`, confirm the data survives. Then delete the StatefulSet and observe that the PVCs do *not* get deleted. |
| **Sat** | **PAID SESSION (~2 hr).** EBS CSI driver as an addon, with IRSA. gp3 StorageClass. Postgres StatefulSet with a real EBS volume. Delete the pod, watch the volume reattach. Then the important part: delete the StatefulSet, go to the EC2 console, and see the orphaned `available` volume still billing. Delete it. That is the lesson. |

---

### Week 6 — Scaling (Module 08) — 2 sessions, ~$1.00

The most conceptually dense module. Budget the most local prep.

| Day | Work |
|-----|------|
| Mon | Three distinct scalers — be able to state precisely what each one changes: **HPA** (pod count, from metrics), **Cluster Autoscaler / Karpenter** (node count, from unschedulable pods), **VPA** (pod resource requests). They are frequently confused. |
| Tue | HPA in kind: install metrics-server, add a CPU-bound endpoint to the Flask app, load it, watch replicas climb and then settle. Understand the stabilisation window. |
| Wed | PodDisruptionBudget in kind: set `minAvailable`, then `kubectl drain` a kind node and watch the eviction get blocked. This is the cheapest way to learn PDB semantics. |
| Thu | Karpenter on paper: NodePool, EC2NodeClass, consolidation, and how it differs from Cluster Autoscaler's node-group model. |
| **Sat** | **PAID SESSION 1 (~90 min).** Install Karpenter. Scale a deployment past node capacity; watch a node get provisioned in ~60 seconds. Scale to zero; watch consolidation remove it. |
| **Sun** | **PAID SESSION 2 (~90 min).** Spot interruption handling. Node termination handler behaviour, PDB interaction under drain, and a rollout that survives a node going away. |

---

### Week 7 — GitOps (Module 09) — 1 session, ~$0.50

Almost entirely local. This is where 24 GB pays for itself.

| Day | Work |
|-----|------|
| Mon | GitHub Actions: build on push, tag with the commit SHA (**never** `latest`), push to Docker Hub. Store the Docker Hub token as a repo secret. |
| Tue | Kustomize: base plus `overlays/dev` and `overlays/prod`. Understand `kustomize build` output before ArgoCD ever renders it. |
| Wed | ArgoCD into `kind-lab`. Application manifest pointing at your repo. Auto-sync on. Then test self-heal: `kubectl scale` a deployment by hand and watch ArgoCD revert it within seconds. |
| Thu | Spin up `kind-staging` (second cluster, ports 8081/8443) and register it with ArgoCD. Multi-cluster GitOps for $0.00. |
| **Sat** | **PAID SESSION (~90 min).** Register the EKS cluster as an ArgoCD target. Put an ALB in front of the ArgoCD UI. Prove one commit deploys to EKS with no `kubectl apply` anywhere in the loop. |

---

### Week 8 — Observability, security, and the private-networking comparison (Modules 10, 10b) — 1 session, ~$0.60

| Day | Work |
|-----|------|
| Mon | `kube-prometheus-stack` in kind. Budget ~3 GB. Find where each of these lives: node CPU, pod memory, container restarts, HTTP request rate from your Flask app. |
| Tue | Instrument Flask with `prometheus_client`, add a ServiceMonitor, build one Grafana dashboard you would actually look at. |
| Wed | NetworkPolicy in kind. Default-deny ingress in a namespace, then allow exactly the one path your app needs. Prove the block with `kubectl exec ... curl`. Note that kind's default CNI may not enforce policy — install Calico if so, and understand *why* that matters on EKS too. |
| Thu | `trivy k8s` and `trivy image` against your own Flask image. Fix one real CVE by changing the base image. Add the scan as a GitHub Actions step. |
| **Sat** | **PAID SESSION (~90 min).** Enable EKS audit logging, generate some API calls, read them in CloudWatch — then **turn it off**, because it bills. Then rebuild with `privateNetworking: true` and a NAT gateway, look at what changed in the VPC, and check the hourly rate. Tear it down within the hour. That comparison is the whole reason the rest of the plan avoids NAT. |

---

## 5. Assessment checkpoints

Three graded self-tests. Timed, closed-book, no scrollback. If you fail one, repeat that phase's break/fix drills rather than pressing on.

**Checkpoint A — end of Week 2 (local, 45 min).**
From an empty kind cluster: deploy a two-service app, expose one via Ingress on localhost:8080, package it as a Helm chart with a templated tag, upgrade it, break it, roll it back. No references.

**Checkpoint B — end of Week 5 (paid, 60 min inside a normal session).**
`up.sh`, then: a pod that reads S3 via IRSA, fronted by an ALB Ingress, with a StatefulSet on an EBS gp3 volume. Then `down.sh` and a fully clean `verify-clean.sh`. Time it.

**Checkpoint C — end of Week 8 — the definition of done.**
From a fresh `git clone` and an empty AWS account: an application exposed through an ALB, backed by EBS persistent storage, deployed by ArgoCD from Git, with pods authenticating to S3 via IRSA. Under 30 minutes. No documentation. Then tear it down and watch the bill return to zero.

---

## 6. Cost ledger

Fill this in as you go, from Cost Explorer filtered to `Project=eks-lab`. If a week comes in more than 2× its estimate, stop and find the orphaned resource before starting the next module.

| Week | Module(s) | Sessions | Est. | Actual | Notes |
|------|-----------|----------|------|--------|-------|
| 1 | 01 | 0 | $0.00 | | |
| 2 | 02, 03, 03b | 0 | $0.00 | | |
| 3 | 04, 05 | 2 | $0.60 | | |
| 4 | 06 | 1–2 | $0.70 | | |
| 5 | 07 | 1–2 | $0.60 | | |
| 6 | 08 | 2 | $1.00 | | |
| 7 | 09 | 1 | $0.50 | | |
| 8 | 10, 10b | 1 | $0.60 | | |
| | | | **≈$4–6** | | |

Control plane is ~$0.10/hr on a current version. Drifting into extended support is $0.60/hr — pin the version and re-check it at the start of every module.

---

## 7. Reading list — one canonical source per topic

Use the official docs. Read the concept page once, then the API reference when you need a field.

| Topic | Source |
|-------|--------|
| Core objects, probes, resources | kubernetes.io Concepts → Workloads, then the API reference |
| RBAC | kubernetes.io → Reference → Access Control |
| Ingress | kubernetes.io Concepts → Services, Load Balancing, Networking |
| Helm | helm.sh → Docs → Chart Template Guide |
| kind | kind.sigs.k8s.io → User Guide → Configuration |
| EKS cluster config | eksctl.io schema reference |
| IRSA / Pod Identity | AWS EKS User Guide → Security → IAM |
| AWS Load Balancer Controller | kubernetes-sigs.github.io/aws-load-balancer-controller |
| EBS CSI | AWS EKS User Guide → Storage |
| Karpenter | karpenter.sh → Concepts |
| ArgoCD | argo-cd.readthedocs.io → Operator Manual |
| Prometheus operator | prometheus-operator.dev → Design |

Skip anything titled "Kubernetes in 10 minutes."

---

## 8. Recall drill bank

Five minutes at the start of each session. Answer out loud before checking. Rotate; revisit anything you get wrong two sessions later.

**Objects**
1. A Service has no endpoints. Name three causes, in order of likelihood.
2. What is the difference between a liveness and a readiness probe failure?
3. Which QoS class does a pod get with requests set and limits unset?
4. Why does a mounted ConfigMap update live but an env var not?
5. `CrashLoopBackOff` with empty logs — what happened?

**Cluster**
6. What does `kubectl drain` do that `kubectl delete node` does not?
7. What are the four control-plane components and what does each decide?
8. Where does kubelet get its pod list from on a kubeadm node?

**AWS**
9. Trace the IRSA chain from ServiceAccount annotation to an S3 API call.
10. NLB vs ALB — one sentence each on when to use which.
11. What is still billing after `eksctl delete cluster` succeeds? Name three.
12. What does a NAT gateway cost per month if you leave one running?
13. Reclaim policy `Delete` vs `Retain` — which one costs money and when?

**GitOps and scaling**
14. HPA, Cluster Autoscaler, VPA — what does each one change?
15. What does ArgoCD do when you `kubectl scale` a synced deployment by hand?
16. Why tag images with the commit SHA rather than `latest`?

---

## 9. If you fall behind

Do not compress. Drop, in this order:

1. Module 10b (the private-networking rebuild) — interesting, not load-bearing
2. Week 6's second paid session (spot interruption) — read about it instead
3. Module 03b (kubeadm) — but only 