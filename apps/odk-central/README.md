# ODK Central

```bash
kubectl create secret generic odk-central-vars \
    --from-literal=PGPASSWORD='xxx' \
    --from-literal=EMAIL_USER='xxx' \
    --from-literal=EMAIL_PASSWORD='xxx' \
    --from-literal=S3_ACCESS_KEY='xxx' \
    --from-literal=S3_SECRET_KEY='xxx' \
    --dry-run=client \
    --namespace='field' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-secret.yaml
```
