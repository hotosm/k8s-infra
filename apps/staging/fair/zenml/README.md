# ZenML

Deployed by the `fair-staging` ApplicationSet (`../../fair.yaml`).
Pipeline pods run in `zenml-pipelines-stage` (in-cluster orchestrator, RBAC in
`../zenml-orchestrator-role.yaml`). See `../../../fair/README.md` for the layout.
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

!! Make sure this is applied if regenerating the secret !!

## Configuration

See the shared runbook in [`apps/fair/zenml/opentofu/README.md`](../../../fair/zenml/opentofu/README.md).

## How to reset ZenML staging password

Users persist in the `zenml-db-staging` DB across PR deploys. Passwords are
bcrypt hashes, so they can't be recovered, only replaced.

```bash
# 1. Generate a hash (prompts for the new password)
kubectl -n fair-staging exec -it deploy/<zenml-deployment> -- python -c \
  'import bcrypt, getpass; print(bcrypt.hashpw(getpass.getpass().encode(), bcrypt.gensalt()).decode())'

# 2. Open psql interactively (passing the hash via -c lets the shell mangle the $ chars)
kubectl -n postgres exec -it zenml-db-staging-1 -- psql -U postgres zenml
```

```sql
begin;
update "user" set password = '<hash>' where name = '<username>';  -- expect UPDATE 1
commit;
```
