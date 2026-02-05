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

First create `secret.yaml` for the storage config:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: flyte-s3-creds
  namespace: flyte
type: Opaque
stringData:
  013-storage-secrets.yaml: |
    storage:
      stow:
        config:
          access_key_id: "xxx"
          secret_key: "xxx"
```

Then seal the secret:

```bash
kubeseal -f secret.yaml -w sealed-s3-creds.yaml
```

Finally, create the db sealed secret:

```bash
kubectl create secret generic flyte-db-password \
    --from-literal=pass.txt='xxx' \
    --dry-run=client \
    --namespace='flyte' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-db-password.yaml
```
