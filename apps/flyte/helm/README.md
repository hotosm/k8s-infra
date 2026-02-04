# Flyte Setup

```bash
cd scripts
bash create-s3-bucket.sh hotosm-fair-flyte

# NOTE we won't add intelligent tiering until we need it,
# perhaps for a specific path / criteria, as the models
# should be available for inference 90/180 days after
# they are generated.
#
# bash add-s3-intelligent-tiering.sh hotosm-fair-flyte
```

```bash
kubectl create secret generic flyte-s3-creds \
    --from-literal=accesskey="xxx" \
    --from-literal=secretkey="xxx" \
    --dry-run=client \
    --namespace='flyte' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-s3-creds.yaml
```

```bash
kubectl create secret generic flyte-db-password \
    --from-literal=postgres-password='xxx' \
    --dry-run=client \
    --namespace='flyte' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-db-password.yaml
```
