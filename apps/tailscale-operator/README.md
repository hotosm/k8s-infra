# Tailscale Kubernetes Operator

This app installs the Tailscale Kubernetes Operator via Helm and uses a
pre-created secret named `operator-oauth` for OAuth credentials.

## Prerequisites

Guide here https://tailscale.com/docs/features/kubernetes-operator.

## Secret

The Helm chart will use a pre-created secret named `operator-oauth` if
`oauth.clientId` and `oauth.clientSecret` are not set in Helm values.

The secret must contain these exact keys:

- `client_id`
- `client_secret`

Create and seal it after replacing the placeholder values:

```bash
kubectl create secret generic operator-oauth \
    --from-literal=client_id='kJ81V5Lgqs11CNTRL' \
    --from-literal=client_secret='tskey-client-kJ81V5Lgqs11CNTRL-AFHrHnUzdfa4BRmc8iT6ga2zBsgegNpRQ' \
    --dry-run=client \
    --namespace='tailscale' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-secret.yaml

rm secret.yaml
```

## Sources

- https://tailscale.com/docs/features/kubernetes-operator
- https://tailscale.com/docs/features/kubernetes-operator/how-to/cluster-ingress
- https://tailscale.com/docs/features/kubernetes-operator/how-to/customize
