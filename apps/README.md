# ArgoCD Apps

- Configurations inside this directory are scanned by ArgoCD,
  and automatically deployed into the cluster.

Access Argo dashboard:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080
```
