# Login Backend & Frontend

HOTOSM Login service providing OSM OAuth integration and custom login UI.

## Architecture

- **Backend** (FastAPI): Handles `/api/*` and `/me` routes
- **Frontend** (React SPA): Serves `/login` route
- **Hanko**: Root path `/` (deployed separately, see [../hanko](../hanko))

All services share the `login.hotosm.org` domain using path-based routing.

## DNS and TLS

- **external-dns**: Auto-provisions Route53 DNS from ingress annotations
- **cert-manager**: Auto-provisions Let's Encrypt TLS certificates

No manual DNS/certificate setup required.

## Re-creating The Secrets

**IMPORTANT**: Requires cluster access. `kubeseal` needs to fetch the public key from the cluster's sealed-secrets controller.

1. Login to the k8s cluster
2. Set your secret values:

```bash
COOKIE_SECRET="your-cookie-secret-min-32-bytes"
OSM_CLIENT_ID="your-osm-client-id"
OSM_CLIENT_SECRET="your-osm-client-secret"
```

3. Create and seal the secret:

```bash
# Create temporary secret
kubectl create secret generic login-backend-secrets \
  --from-literal=cookie-secret="$COOKIE_SECRET" \
  --from-literal=osm-client-id="$OSM_CLIENT_ID" \
  --from-literal=osm-client-secret="$OSM_CLIENT_SECRET" \
  --namespace=login \
  --dry-run=client -o yaml > /tmp/login-secret.yaml

# Seal it
kubeseal --format=yaml \
  --namespace=login \
  < /tmp/login-secret.yaml \
  > sealed-secrets.yaml

# Clean up
rm /tmp/login-secret.yaml
```

4. Commit `sealed-secrets.yaml` to this repository

## Deployment

ArgoCD automatically deploys from this directory. Manual sync:

```bash
argocd app sync login
```

## Verification

```bash
# Check pods
kubectl get pods -n login

# Check services
kubectl get svc -n login

# Check ingress
kubectl get ingress -n login

# View logs
kubectl logs -n login -l app=login-backend
kubectl logs -n login -l app=login-frontend
```

## Related

- Source: https://github.com/hotosm/login
- Hanko config: [../hanko](../hanko)
