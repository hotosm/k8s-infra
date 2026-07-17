# eoAPI - fAIr

Minimal eoAPI (STAC only - pgSTAC + stac-fastapi). Deployed by the
`fair-staging` ApplicationSet (`../../fair.yaml`). STAC catalog data
lives in the `fair-stac` CNPG cluster in `postgres`.

## DB creds sealed secret

Lives at `apps/staging/fair/fair-stac-db-creds.yaml` (top-level of the
ApplicationSet's path source, not this subdir):

```bash
kubectl create secret generic fair-stac-db-creds \
    --from-literal=username='fair-stac' \
    --from-literal=password='xxx' \
    --from-literal=host='fair-stac-db-rw.postgres.svc.cluster.local' \
    --from-literal=port=5432 \
    --from-literal=database='fair-stac' \
    --dry-run=client \
    --namespace='fair-staging' \
    -o yaml > secret.yaml

# Add annotation so it survives PR closure:
#   argocd.argoproj.io/sync-options: Prune=false,Delete=false

kubeseal -f secret.yaml -w ../fair-stac-db-creds.yaml
```
