# eoAPI - fAIr

- fAIr needs a STAC.
- eoAPI is a nicely packaged STAC service, including
  pgSTAC, stac-fastapi, extension support etc.
- We deploy a minimal instance of eoAPI with only
  the STAC components enabled.

## DB Credentials Sealed Secret

```bash
# Credentials for specific databases
kubectl create secret generic fair-stac-db-creds \
    --from-literal=username='fair-stac' \
    --from-literal=password='xxx' \
    --from-literal=host='fair-stac-db-rw.postgres.svc.cluster.local' \
    --from-literal=port=5432 \
    --from-literal=database='fair-stac' \
    --dry-run=client \
    --namespace='fair' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w fair-stac-db-creds.yaml
```
