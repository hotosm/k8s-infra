# Velero

## Create Secret

Create creds file named `credentials`:

```toml
[default]
aws_access_key_id=<REDACTED>
aws_secret_access_key=<REDACTED>
```

Create sealed-secret:

```bash
kubectl create secret generic velero-s3-creds \
  --from-file=cloud=./credentials \
  --namespace velero \
  --dry-run=client -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-secret.yaml
```

> [!NOTE]
> Velero needs a secret with a single key `cloud`, containing
> the AWS credentials file:
> credentials:
>   useSecret: true
>   secretContents:
>     cloud: |
>       [default]
>       aws_access_key_id = {your-minio-access-key}
>       aws_secret_access_key = {your-minio-secret-key}
