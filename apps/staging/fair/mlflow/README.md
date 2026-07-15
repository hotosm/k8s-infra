# MLflow

Deployed by the `fair-staging` ApplicationSet (`../../fair.yaml`).
Persistent state:

- **Backend DB:** `mlflow-db` CNPG cluster in `postgres`.
- **Artifacts:** S3 `hotosm-fair-mlflow` (intelligent tiering, 180d).

## S3 bucket (one-off)

```bash
cd scripts
bash create-s3-bucket.sh hotosm-fair-mlflow
bash add-s3-intelligent-tiering.sh hotosm-fair-mlflow
```

## Sealed secrets

All three live flat under `apps/staging/fair/`. Add
`argocd.argoproj.io/sync-options: Prune=false,Delete=false` to each.

### `mlflow-s3-creds`

```bash
kubectl create secret generic mlflow-s3-creds \
    --from-literal=AWS_ACCESS_KEY_ID='xxx' \
    --from-literal=AWS_SECRET_ACCESS_KEY='xxx' \
    --dry-run=client \
    --namespace='fair-staging' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w ../mlflow-s3-creds.yaml
```

### `mlflow-db-creds`

```bash
kubectl create secret generic mlflow-db-creds \
    --from-literal=username='xxx' \
    --from-literal=password='xxx' \
    --dry-run=client \
    --namespace='fair-staging' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w ../mlflow-db-creds.yaml
```

### `mlflow-admin-password`

```bash
kubectl create secret generic mlflow-admin-password \
    --from-literal=adminUsername='admin' \
    --from-literal=adminPassword='xxx' \
    --dry-run=client \
    --namespace='fair-staging' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w ../mlflow-admin-password.yaml
```

## Migrations

Set `backendStore.databaseMigration: true`, sync, wait for the job, flip back.
