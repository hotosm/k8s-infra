# ZenML

## Issues with official chart

1. Only allows MySQL, with Postgres connection clearly being
  possible, but unsupported.
  - **Solution**: we build a custom image to support Postgres,
    [located here](https://github.com/hotosm/fAIr/tree/develop/infra/zenml)
  - We also add `backupStrategy: disabled` to prevent issues running
    the database backup job (we handle backup externally).

2. Secret environment variables cannot be easily injected without
   committing them to Git.
   - **Solution**: kustomization.yaml with deployment patch for
     additional environment variables.

## Using this setup

Create the secret with additional secret env vars:

```bash
# Env var options can be found here:
# https://github.com/zenml-io/zenml/blob/main/docs/book/getting-started/deploying-zenml/deploy-with-docker.md
# E.g. ZENML_STORE_PASSWORD is the database password
# Generate ZENML_SECRETS_STORE_ENCRYPTION_KEY with `openssl rand -hex 32`

kubectl create secret generic zenml-extra-secret-env \
    --from-literal=ZENML_STORE_PASSWORD='xxx' \
    --from-literal=ZENML_SECRETS_STORE_ENCRYPTION_KEY='xxx' \
    --dry-run=client \
    --namespace='zenml' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-extra-secrets.yaml
```

> NOTE
> Setting S3 credentials for an artifact store comes after install:
> https://docs.zenml.io/stacks/stack-components/artifact-stores/s3

## IMPORTANT: A Note On Sync Waves

- I couldn't get the sync order to work here.
- The db migration job from helm tries to run before
  the sealed secret is applied.
- SyncWave orders didn't seem to help.
- As a temp workaround, simply apply the sealed secret
  first, then deploy the app.

## Configiration

See [README file](./opentofu/README.md) in the `opentofu` section.
