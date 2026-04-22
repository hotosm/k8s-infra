# Cluster RBAC

- Simple roles for users in the cluster:
  - Admin is the default
  - Role for read-only and for contractor (namespace scoped).
- This is utilised by Tailscale when accessing the cluster,
  meaning tailscale users marked as either 'read-only' or
  'contractor' will be matched with the relevant RBAC role.
