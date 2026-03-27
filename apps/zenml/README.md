# ZenML

## Issues with official chart

- The official chart only supports MySQL, but Postgres works fine.
- We build a custom image to support Postgres,
  [located here](https://github.com/hotosm/fAIr/tree/develop/infra/zenml).
- We also set `backupStrategy: disabled` to prevent issues running
  the database backup job (we handle backup externally).

## Secrets

Secret env vars are injected via the Helm chart's `environmentSecretKeyRefs`
(available since 0.94.1), referencing a SealedSecret in the cluster.

To rotate or recreate the sealed secret:

```bash
# ZENML_STORE_PASSWORD = database password
# ZENML_SECRETS_STORE_ENCRYPTION_KEY = `openssl rand -hex 32`

kubectl create secret generic zenml-extra-secret-env \
    --from-literal=ZENML_STORE_PASSWORD='xxx' \
    --from-literal=ZENML_SECRETS_STORE_ENCRYPTION_KEY='xxx' \
    --dry-run=client \
    --namespace='zenml' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-extra-secrets.yaml
```

The sealed secret uses a sync-wave annotation (`-5`) so ArgoCD
applies it before the Helm chart's db migration job runs.

## Configuration

See [README file](./opentofu/README.md) in the `opentofu` section.
