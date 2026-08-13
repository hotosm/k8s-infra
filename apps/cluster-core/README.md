# Cluster Core

Cluster-wide resources that aren't tied to any single app.

## RBAC

- Simple roles for users in the cluster:
  - Admin is the default.
  - `viewers` group: cluster-wide read-only (`view` ClusterRole).
  - `contractor` group: cluster-wide read-only (`view` ClusterRole)
    plus `edit` on the namespaces listed in `values.yaml`.
- This is utilised by Tailscale when accessing the cluster,
  meaning tailscale users marked as either 'viewers' or
  'contractor' will be matched with the relevant RBAC role.

## StorageClasses

Both back onto the `aws-ebs-csi-driver` and use `WaitForFirstConsumer` so the
EBS volume is created in the same AZ as the pod that claims it.

- `gp3` (cluster default): `reclaimPolicy: Retain`. Used by the CNPG databases
  in `databases/`, so deleting a PVC leaves the volume behind to be recovered.
- `gp3-ephemeral`: `reclaimPolicy: Delete`, for disposable scratch space only.
  Currently used by the windmill `tm-export` worker group, which claims one as a
  generic ephemeral volume so it is created and destroyed with the pod.

`provisioner`, `parameters` and `reclaimPolicy` are immutable once a
StorageClass exists - changing any of them needs a manual delete and recreate,
an ArgoCD sync alone will fail.
