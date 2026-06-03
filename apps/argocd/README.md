# ArgoCD

Installs ArgoCD from the upstream `cluster-install` manifests
and layers on the following customisations:

- **Tailscale Service exposure** (`argocd-server-svc-patch.yaml`)
  - annotates the `argocd-server` Service with
  `tailscale.com/expose: "true"` and `tailscale.com/hostname: argocd`,
  so anyone in the tailnet can reach the UI at
  `http://argocd` (MagicDNS) without `kubectl port-forward`.
- **`server.insecure: "true"`** (`argocd-cmd-params-cm-patch.yaml`)
  - the Tailscale proxy doesn't terminate TLS, so `argocd-server`
  runs plain HTTP (the tailnet itself is WireGuard-encrypted).
- **Read-only `contractor` account** (`argocd-cm-patch.yaml` +
  `argocd-rbac-cm-patch.yaml`) - local account bound to the
  built-in `role:readonly`, for contractors to view sync /
  deploy status without being able to modify anything.

## Setting the contractor password

ArgoCD does not let you declare a password in a ConfigMap.
After the account is created, an admin must set it via the
CLI:

```bash
# Log in as admin
argocd login argocd --username admin --plaintext

# Set the contractor password (you will be prompted twice)
argocd account update-password \
  --account contractor \
  --current-password '<admin-password>'
```

Share the resulting password with the contractor.
