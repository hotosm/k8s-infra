# Secrets Management In Kubernetes

From skillshare session 26/11/2025

## Video Recording

<iframe
  src="https://drive.google.com/file/d/18XEJHWgBOR-ptPUYGyH0E3MJCzHNhh_s/preview"
  width="100%"
  height="480"
  allow="autoplay; fullscreen"
  allowfullscreen
></iframe>

## How do secrets work in Kubernetes?

- Kubernetes stores secrets as plain text = compromised cluster = compromised secrets.
- This is generally fine though: all depends on your **threat model**.
- SealedSecrets facilitate a GitOps approach and keep secrets outside
  of password managers, and inside Git repos - fully encrypted.

## Install Bitnami Sealed Secrets

1. Deploy using ArgoCD:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  project: default
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    targetRevision: 2.17.3
    helm:
      releaseName: sealed-secrets-controller
      valuesObject:
        fullnameOverride: sealed-secrets-controller
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

2. Install `kubeseal`:

- Present in `ghcr.io/spwoodcock/awscli-kubectl:latest`
- Or install manually: https://github.com/bitnami-labs/sealed-secrets/releases

3. Backup Sealed Secrets Key:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >main.key
```

Store this securely!

## Create Sealed Secrets

### Using --from-literal (simple values)

```bash
kubectl create secret generic cloudflare-api \
    --from-literal=ACCOUNT_ID=your-account-id \
    --from-literal=TOKEN=your-token \
    --dry-run=client \
    --namespace='gateway' \
    -o yaml > secret.yaml
```

### Using --from-file (file contents)

```bash
# Single file
kubectl create secret generic my-secret \
    --from-file=config.json \
    --dry-run=client -o yaml > secret.yaml

# Multiple files
kubectl create secret generic tls-secret \
    --from-file=tls.crt \
    --from-file=tls.key \
    --dry-run=client -o yaml > secret.yaml

# Custom key name
kubectl create secret generic my-secret \
    --from-file=my-config=config.json \
    --dry-run=client -o yaml > secret.yaml
```

### Seal and commit

```bash
kubeseal -f secret.yaml -w sealed-secret.yaml
rm secret.yaml
git add sealed-secret.yaml
```

## Update Existing Sealed Secret

1. Get current secret from cluster:

```bash
kubectl get secret cloudflare-api -n gateway -o yaml
```

2. View current values:

```bash
kubectl get secret cloudflare-api -n gateway -o jsonpath='{.data.TOKEN}' | base64 -d
```

3. Recreate with new values:

```bash
kubectl create secret generic cloudflare-api \
    --from-literal=ACCOUNT_ID=new-account-id \
    --from-literal=TOKEN=new-token \
    --dry-run=client \
    --namespace='gateway' \
    -o yaml > secret.yaml
```

4. Re-seal and commit:

```bash
kubeseal -f secret.yaml -w sealed-secret.yaml
rm secret.yaml
git add sealed-secret.yaml
git commit -m "Update sealed secret"
```

## Other Options

- Cloud provider integrations (AWS Secrets Manager, etc.) - not portable
- External Secrets Operator with Hashicorp Vault - requires external service
- SealedSecrets = simple, portable, GitOps-friendly
