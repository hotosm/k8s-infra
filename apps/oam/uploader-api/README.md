# OAM Uploader API

Imagery uploader at <https://upload.imagery.hotosm.org>. Uploads go presigned
direct-to-S3, then run as Argo Workflows (validate → COG → metadata → STAC
register), executed by the cluster-wide Argo controller from ScaleODM.

Deployed by the `uploader-api` sources in `apps/oam.yaml` - **currently
commented out**, pending the eoAPI migration. Uncomment once the four secrets
below exist.

## Secrets (one-time bootstrap)

Seal into `apps/oam/` (`../`), not this dir - the git source is non-recursive,
so a manifest in a component subdir is never applied.

`PGSTAC_DB_PASSWORD` must match the pgstac cluster; the uploader is in a
different namespace to that secret, so the password is duplicated here:

```bash
kubectl -n oam get secret oam-eoapi-pgstac-prod-db-creds \
  -o go-template='{{range $k, $v := .data}}{{$k}}: {{$v | base64decode}}{{"\n"}}{{end}}'
```

App env - AWS keys need read/write on `oin-hotosm-temp`, `DB_PASSWORD` must
match `oam-uploader-db-creds`:

```bash
kubectl create secret generic oam-uploader-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=COOKIE_SECRET=(openssl rand -hex 32) \
  --from-literal=DB_PASSWORD="xxx" \
  --from-literal=PGSTAC_DB_PASSWORD="xxx" \
  --namespace=oam --dry-run=client -o yaml \
  | kubeseal -o yaml > ../oam-uploader-secrets.yaml
```

Pipeline step S3 credentials (same IAM user is fine):

```bash
kubectl create secret generic oam-uploader-s3 \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --from-literal=AWS_DEFAULT_REGION="us-east-1" \
  --namespace=oam --dry-run=client -o yaml \
  | kubeseal -o yaml > ../oam-uploader-s3.yaml
```

Workflow log archiving - the artifact-repository secret is resolved in the
workflow's namespace, so re-seal the `odm` copy
(`apps/scaleodm/argo-logs-s3-creds.yaml`) for `oam`:

```bash
kubectl create secret generic argo-logs-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --namespace=oam --dry-run=client -o yaml \
  | kubeseal -o yaml > ../argo-logs-s3-creds.yaml
```

CNPG bootstrap credential, in the `postgres` namespace:

```bash
kubectl create secret generic oam-uploader-db-creds \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="oam_uploader" \
  --from-literal=password="xxx" \
  --namespace=postgres --dry-run=client -o yaml \
  | kubeseal -o yaml > ../../../databases/oam-uploader-db-creds.yaml
```

## Smoke test

```bash
kubectl -n oam run curl-test --rm -it --restart=Never \
  --image=curlimages/curl \
  --command -- curl -v http://uploader-api.oam.svc.cluster.local:8080/__lbheartbeat__
```

Then upload a small GeoTIFF at <https://upload.imagery.hotosm.org> and watch
`kubectl -n oam get workflows` until it reports Succeeded.
