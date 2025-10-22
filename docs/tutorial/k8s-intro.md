# Kubernetes Introduction

From skillshare session 15/10/2025

## Video Recording

<iframe
  src="https://drive.google.com/file/d/1sIHFzOcloF5CE0LIFsi-fSRKwXQcq9Gx/preview"
  width="640"
  height="480"
  allow="autoplay"
></iframe>

## What is Kubernetes?

- Building on the concept of containers to deploy applications,
  Kubernetes (often abbreviated as *k8s*) is an orchestration tool,
  for linking multiple servers together, sharing load, and running
  resources across the cluster.

- Kubernetes is **delcarative**. You specify your 'desired'
  state, e.g. I want 2 copies of this app running, and
  the Kubernetes control plane will try it's best to keep
  everything you specified running. Hence 'self-healing'.

- At it's core, Kubernetes is a collection of tools mostly maintained
  by the Cloud Native Computing Foundation(CNCF):
  - **Container runtime**: low level runtime such as `containerd` + `runc`.
  - **Key-value database**: storing the state of the cluster, `etcd`.
  - **Network router**: route traffic between services, `kube-proxy`.
  - **DNS server**: make services discoverable, `CoreDNS`.
  - **Scheduler**: assign workloads (Pods) to suitable nodes.
  - **Node agent**: runs on each node, managing pods / containers, `kubelet`.
  - **Plugins**: storage and networking extensions built on standard
    Linux tools.

!!! note

        As we are running multiple machines across a network, or
        possibly multiple networks, we need to consider distributed
        computing concepts.

        Running via docker is pretty simple, as you only have a single
        machine. Running via Kubernetes requires some thought to
        networking across machines, and shared distributed storage
        methods.

## Node types

- 'Nodes' are simply machines in the cluster.

- There are two types:
  - **Control plane**: run the core components needed for the cluster,
    manage state, and run commands to keep reality in line with
    desired state.
  - **Worker**: the machines that run actual workloads, such as
    applications, background jobs, data pipelines, etc.

- Note that worker nodes can optionally have GPUs attached, and be
  designated 'GPU nodes'.

## Resource types

- There are too many to list here, but the key ones you need are:
  - **Pods**: essentially a wrapper around a container (± initContainer).
  - **Deployment**: defines how many copies of a pod should run across nodes.
  - **Service**: provides a network endpoint and load balancing for pods.
  - **Ingress**: exposes HTTP/HTTPS applications externally, often using
    domain names and TLS certificates.
  - **ConfigMap / Secret**: define configuration or credentials for apps.
  - **Namespace**: a separated group of resources, for better organisation /
    isolation (for example, group all pods that make up a single app). Also
    helps with namespace-level access control when dealing with many
    contractors / devs.

!!! note

    Typically you will be using Deployments to manage your applications.
    Depoyments manage a ReplicaSet underneath, i.e. a specific number
    of pods, plus the actual pods that are running. ReplicaSets are
    rarely used on their own, unless specific fine grained control
    is needed.

    There are two other type of 'Sets' being the StatefulSet and DaemonSet.

    **DaemonSets**: runs one pod per node. Useful for daemon such a log
      collectors or monitoring agents.
    **StatefulSet**: for stateful apps that need stable, unique pod
      identities and persistent storage. We will cover persistent
      storage in a [future tutorial](storage.md).

## YAML Manifests

- Each resource in Kubernetes can be defined as a YAML.

- An example deployment for two Nginx pod replicas:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 2                     # desired number of Pod replicas
  selector:
    matchLabels:
      app: nginx                  # label used to match Pods
  template:
    metadata:
      labels:
        app: nginx                # applied to the Pods themselves
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80   # port exposed by the container
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
```

## Practical

### Running Kubernetes locally with TalosOS

1. Install Docker.
2. Install TalosCTL: `curl -sL https://talos.dev/install | sh`.
3. Create a local cluster: `talosctl cluster create`.
4. Wait a minute, then run workloads with `kubectl`.
5. Destroy the cluster `talosctl cluster destroy`.

### Running commands in the cluster

Either install tools manually, or use my helper image:

```bash
# Set alias, place in ~/.bashrc if you prefer
alias aws-shell='docker run --rm -it --name aws-cli -v $HOME:/root -v /var/run/docker.sock:/var/run/docker.sock --workdir /root --network host ghcr.io/spwoodcock/awscli-kubectl:latest'

aws-shell

# Connect to cluster
kcc

# View cluster details
kubectl get node
kubectl get pods --all-namespaces

# Change namespace
ns
```

### Deploy Nginx test app

- Using the Nginx deployment YAML defined [above](#yaml-manifests),
  create the file `nginx.yaml`.

- Next, apply the deployment to the cluster:

```bash
kubectl apply -f nginx.yaml

kubectl get pods
```

- Let's scale the deployment to 4 replicas:

```bash
kubectl scale deployment nginx-deployment --replicas=4
```

- View the details of a pod:

```bash
kubectl get pods
kubectl describe pod/nginx-deployment-xxxx-xxxx
kubectl logs pod/nginx-deployment-xxxx-xxxx
```

- Then delete the deployment:

```bash
kubectl delete -f nginx.yaml
```
