# ZenML

Deployed by the `fair-staging` ApplicationSet (`../../fair.yaml`).
Pipeline pods spawn in `fair-staging` via `../zenml-orchestrator-role.yaml`.
DB: `zenml-db-staging` CNPG cluster in `postgres`.

## Chart notes

- Official chart is MySQL-only; we use a custom Postgres-capable image
  ([hotosm/fAIr/infra/zenml](https://github.com/hotosm/fAIr/tree/develop/infra/zenml)).
- `backupStrategy: disabled` - WAL archival handled by CNPG.

## Secrets

Env vars injected via `environmentSecretKeyRefs` (chart 0.94.1+):

```bash
# ZENML_STORE_PASSWORD = db password
# ZENML_SECRETS_STORE_ENCRYPTION_KEY = openssl rand -hex 32

kubectl create secret generic zenml-extra-secret-env \
    --from-literal=ZENML_STORE_PASSWORD='xxx' \
    --from-literal=ZENML_SECRETS_STORE_ENCRYPTION_KEY='xxx' \
    --dry-run=client \
    --namespace='fair-staging' \
    -o yaml > secret.yaml

# Annotate with argocd.argoproj.io/sync-options: Prune=false,Delete=false

kubeseal -f secret.yaml -w ../zenml-extra-secret-env.yaml
```

Sync-wave `-5` on the sealed secret ensures it's applied before the
chart's db migration job.

## Configuration

See [`opentofu/README.md`](./opentofu/README.md).
