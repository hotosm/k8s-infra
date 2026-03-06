As of 06/03/2026 these secret vars are used by Field-TM:

```bash
kubectl create secret generic field-tm-prod-secrets \
    --from-literal=ENCRYPTION_KEY='xxx' \
    --from-literal=FTM_DB_PASSWORD='xxx' \
    --from-literal=ODK_CENTRAL_USER='xxx' \
    --from-literal=ODK_CENTRAL_PASSWD='xxx' \
    --from-literal=QFIELDCLOUD_USER='xxx' \
    --from-literal=QFIELDCLOUD_PASSWORD='xxx' \
    --from-literal=OSM_CLIENT_ID='xxx' \
    --from-literal=OSM_SECRET_KEY='xxx' \
    --from-literal=OSM_CLIENT_SECRET='xxx' \
    --from-literal=SENTRY_DSN='xxx' \
    --from-literal=RAW_DATA_API_AUTH_TOKEN='xxx' \
    --dry-run=client \
    --namespace='field' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-secret.yaml
```
