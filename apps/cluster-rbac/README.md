# Cluster RBAC

- Simple roles for users in the cluster:
  - Admin is the default.
  - `viewers` group: cluster-wide read-only (`view` ClusterRole).
  - `contractor` group: cluster-wide read-only (`view` ClusterRole)
    plus `edit` on the namespaces listed in `values.yaml`.
- This is utilised by Tailscale when accessing the cluster,
  meaning tailscale users marked as either 'viewers' or
  'contractor' will be matched with the relevant RBAC role.
