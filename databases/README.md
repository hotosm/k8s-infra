# Databases

- Databases deployed by ArgoCD and operated by CloudNativePG.
- Stored in the same namespace `postgres` for easier management.

## Secrets

### S3 Backup Credentials

- We include S3 credentials and a configured db backup bucket.

```bash
# S3 credentials for backup
kubectl create secret generic s3-creds \
    --from-literal=access-key-id='xxx' \
    --from-literal=secret-access-key='xxx' \
    --dry-run=client \
    --namespace='postgres' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w s3-creds.yaml
```

### Database Credentials

- Each database has a configured user/pass.

```bash
# Credentials for specific databases
kubectl create secret generic hanko-db-creds \
    --from-literal=username='hanko' \
    --from-literal=password='xxx' \
    --dry-run=client \
    --namespace='postgres' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w hanko-db-creds.yaml
```
