# Secrets Management In Kubernetes

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

- This should be present in the pre-built util image `ghcr.io/spwoodcock/awscli-kubectl:latest`.
- Otherwise install it manually: https://github.com/bitnami-labs/sealed-secrets/releases

3. Backup Sealed Secrets Key!

- After the sealed secrets operator is deployed, it's a good
idea to backup the main key:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >main.key
```

This should be stored super securely!

## Use Sealed Secrets

- Sealed secrets are essentially interchangable with Kubernetes secrets.
- Deploying a sealed secret create a Kubernetes secret.
- 'Sealing' the secret essentially allows it to just live inside version
  control, fully encrypted.
- When the sealed secret is applied to the cluster, the operator unseals
  the content before applying it.

1. Create a secret YAML:

```bash
kubectl create secret generic cloudflare-api \
    --from-literal=ACCOUNT_ID=your-account-id \
    --from-literal=TOKEN=your-token \
    --from-literal=TUNNEL_NAME=homelab-k8s-ingress-tunnel \
    --dry-run=client \
    --namespace='gateway' \
    -o yaml > secret.yaml
```

2. Seal the secret

```bash
kubeseal -f secret.yaml -w sealed-secret.yaml
```

3. Add the `sealed-secret.yaml` to your Git tracker, and delete the
   temporary `secret.yaml`.

## Other Options

- Kubernetes has lots of options, including externally managed
  secret integration into AWS.
- Many people use these cloud provider offered solutions, but they
  are not portable or cloud agnostic - they tie you in.
- This can be made more agnostic using the `External Secrets Operator`,
  but still ties you into using an external service, e.g. Hashicorp Vault.
