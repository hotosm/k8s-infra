# Kubernetes Storage

Kubernetes doesn't provide storage - you need an external system.

## Options

### Local/HostPath

- Data stored directly on node disk.
- Fast but not portable, no redundancy.
- Use only for caching, logs, ephemeral data.

### Longhorn

- Simple replicated storage across nodes.
- Lightweight, but not very performant in prod.
- Easy setup, good for homelabs and small clusters.

### Cloud Volumes (AWS EBS, GCP PD, Azure Disk)

- Fully managed by cloud provider.
- Extremely reliable, zero ops overhead.
- Trade-off: vendor lock-in and cost.

### Ceph / Rook

- Powerful distributed storage with full control.
- Complex to operate - needs a lot of compute available.
- Rock-solid, but only for large on-prem deployments with expertise.

### NFS

- Simple shared storage.
- Easy setup, universal compatibility.
- Performance depends on NFS server.
- Fine for shared files, avoid for databases.
- Probably also only good for a homelab mostly.

## Quick Guide

- **Homelab** --> Longhorn
- **Production** --> Cloud volumes
- **Large on-prem** --> Ceph (if you have the expertise)
- **Testing/cache** --> Local volumes
- **Shared files** --> NFS
