# MLFlow Setup

```bash
cd scripts
bash create-s3-bucket.sh hotosm-fair-mlflow
# NOTE we have intelligent tiering enabled, as MLFlow experiements
# are likely less relevant after 180 days
bash add-s3-intelligent-tiering.sh hotosm-fair-mlflow
```

```bash
kubectl create secret generic mlflow-s3-creds \
    --from-literal=AWS_ACCESS_KEY_ID='xxx' \
    --from-literal=AWS_SECRET_ACCESS_KEY='xxx' \
    --dry-run=client \
    --namespace='mlflow' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-s3-creds.yaml
```

```bash
kubectl create secret generic mlflow-db-creds \
    --from-literal=username='xxx' \
    --from-literal=password='xxx' \
    --dry-run=client \
    --namespace='mlflow' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-db-creds.yaml
```
