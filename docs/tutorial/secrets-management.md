# Secrets Management In Kubernetes

- Kubernetes stores secrets as plain text = compromised cluster = compromised secrets.
- This is generally fine though: all depends on your threat model.
- SealedSecrets facilitate a GitOps approach and keep secrets outside
  of password managers, and inside Git repos - fully encrypted.
