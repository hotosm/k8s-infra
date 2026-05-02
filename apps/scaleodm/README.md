# ScaleODM

```bash
kubectl create secret generic scaleodm-secrets \
  --from-literal=SCALEODM_DATABASE_URL="postgresql://scaleodm:xxx@scaleodm-db-rw.postgres.svc.cluster.local:5432/scaleodm" \
  --from-literal=AWS_S3_ENDPOINT="https://s3.amazonaws.com" \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=AWS_DEFAULT_REGION="us-east-1" \
  --namespace=drone \
  --dry-run=client -o yaml > secret.yaml
```
