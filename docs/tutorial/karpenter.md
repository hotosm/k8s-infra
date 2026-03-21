# Karpenter Autoscaling

Karpenter provisions EC2 instances on-demand when pods can't be scheduled
on existing nodes, and removes them when they're no longer needed.

## NodePools

We have two NodePools:

- **cpu-autoscale** - general workloads, prefers spot instances
  (`t`, `m`, `c` families, 4 vCPU, gen 6+)
- **gpu-autoscale** - GPU workloads, on-demand only
  (`g5`, `g4dn` families)

Config lives in `apps/karpenter/`.

## Scale to Zero

Both NodePools scale to zero automatically. The `disruption` policy handles
this:

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 30s  # cpu-autoscale
  consolidateAfter: 0s   # gpu-autoscale (expensive, reclaim immediately)
```

Karpenter will consolidate or terminate nodes that are empty or
underutilized. No minimum node count is enforced - if no pods need
Karpenter-managed nodes, all autoscaled nodes are removed.

The **core** EKS managed node group (non-Karpenter) always runs at least
one node for cluster-critical workloads.

## Spot vs On-Demand

The CPU NodePool allows both spot and on-demand, preferring spot
(cheaper). Deployments can request a specific capacity type using
the well-known Karpenter label as a node selector:

```yaml
# Force on-demand (e.g. for stateful or long-running workloads)
nodeSelector:
  karpenter.sh/capacity-type: on-demand

# Force spot (e.g. for batch jobs that tolerate interruption)
nodeSelector:
  karpenter.sh/capacity-type: spot
```

If no selector is specified, Karpenter picks the cheapest option
(usually spot).

The CPU NodePool also applies a `spot=true:PreferNoSchedule` taint.
This means pods without a toleration will **prefer** non-spot nodes
but can still land on spot if nothing else is available. To explicitly
opt into spot nodes, add:

```yaml
tolerations:
  - key: spot
    operator: Equal
    value: "true"
    effect: PreferNoSchedule
```

## GPU Workloads

The GPU NodePool uses a `nvidia.com/gpu=true:NoSchedule` taint.
Pods must explicitly request GPU resources and tolerate the taint:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

## EBS Volume Zone Affinity

Karpenter nodes can launch in any AZ covered by the tagged subnets.
However, **EBS-backed PersistentVolumes are locked to a single AZ**.
If a pod needs an existing EBS PV, Karpenter must launch the node in
the same AZ as the volume.

If no nodes exist in the required AZ and Karpenter fails to provision
one (e.g. capacity issues), the pod will stay Pending. Check:

```bash
# Which AZ does the PV need?
kubectl describe pv <pv-name> | grep "Node Affinity" -A5

# Are subnets available in that AZ?
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=hotosm-production-cluster" \
  --query "Subnets[].{AZ:AvailabilityZone,SubnetId:SubnetId}" \
  --output table
```

For multi-AZ flexibility, consider EFS instead of EBS for shared storage.

## Troubleshooting

```bash
# Check if Karpenter is trying to provision
kubectl get nodeclaim
kubectl describe nodeclaim <name>

# Check NodePool status and limits
kubectl get nodepool
kubectl describe nodepool cpu-autoscale

# View Karpenter controller logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

Common issues:
- **Pod stuck Pending, no nodeclaim** - check pod resource requests,
  node selectors, and tolerations match a NodePool
- **Nodeclaim created but no node** - EC2 capacity issue, subnet/SG
  misconfiguration, or IAM permissions
- **Node created but pod still Pending** - PV zone mismatch or
  disk pressure on existing nodes
