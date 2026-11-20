# Login Staging

Staging copy of [apps/login](../../login), replacing the dev login EC2.

## Architecture

- **Backend** (FastAPI): Handles `/api/*` and `/me` routes
- **Frontend** (React SPA): Serves `/app` route
- **Hanko**: Root path `/` (deployed by this same Argo app, see [./hanko](./hanko))
- **Database**: `login-staging-db`, see [databases/login-staging.yaml](../../../databases/login-staging.yaml)

## DNS and TLS

- **external-dns**: Auto-provisions Route53 DNS for `staging.login.hotosm.org`
- **cert-manager**: Auto-provisions Let's Encrypt TLS certificates

`dev.login.hotosm.org` is a manual DNS record.

## Re-creating The Secrets

**IMPORTANT**: Requires cluster access. Values come from the dev EC2 (`/opt/login/.env` and `/opt/login/hanko-config.yaml`).

1. Login to the k8s cluster
2. Create and seal the secrets:

```bash
# Database credentials
kubectl create secret generic login-staging-db-creds \
  --from-literal=username=hanko \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=postgres \
  --dry-run=client -o yaml \
  | kubeseal --format=yaml > databases/login-staging-db-creds.yaml

# Backend secrets (same keys as prod)
kubectl create secret generic login-backend-secrets \
  --from-literal=DATABASE_URL="postgresql+asyncpg://hanko:$DB_PASSWORD@login-staging-db-rw.postgres.svc.cluster.local:5432/hanko" \
  --from-literal=HANKO_DB_URL="postgresql://hanko:$DB_PASSWORD@login-staging-db-rw.postgres.svc.cluster.local:5432/hanko" \
  --from-literal=COOKIE_SECRET="..." \
  --from-literal=OSM_CLIENT_ID="..." \
  --from-literal=OSM_CLIENT_SECRET="..." \
  --from-literal=LOGIN_INTERNAL_API_KEY="..." \
  --from-literal=SMTP_USER="..." \
  --from-literal=SMTP_PASSWORD="..." \
  --from-literal=LEARNWORLDS_CLIENT_SECRET="..." \
  --from-literal=LINKEDIN_CLIENT_SECRET="..." \
  --namespace=login-staging \
  --dry-run=client -o yaml \
  | kubeseal --format=yaml > apps/staging/login/sealed-secrets.yaml

# Hanko config (EC2 hanko-config.yaml with the database block changed)
kubectl create secret generic hanko-config \
  --from-file=config.yaml=./config.yaml \
  --namespace=login-staging \
  --dry-run=client -o yaml \
  | kubeseal --format=yaml > apps/staging/login/hanko/sealed-config.yaml
```

3. Commit the sealed files to this repository

## Deployment

ArgoCD automatically deploys from this directory. Manual sync:

```bash
argocd app sync login-staging
```

To update, set the image tags in [./helm/values.yaml](./helm/values.yaml) to the new `develop` commit SHA.

## Verification

```bash
kubectl get pods -n login-staging
kubectl get ingress -n login-staging
kubectl get cluster -n postgres login-staging-db
```

## Related

- Source: https://github.com/hotosm/login
- Production: [apps/login](../../login)
