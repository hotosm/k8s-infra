# OAM Uploader API

Imagery uploader at <https://upload.imagery.hotosm.org>. Uploads go presigned
direct-to-S3, then run as Argo Workflows (fetch → validate → COG → metadata →
STAC register), executed by the cluster-wide Argo controller from ScaleODM.

Deployed by the `uploader-api` sources in `apps/oam.yaml`: chart from GHCR
(`oci://ghcr.io/hotosm/charts/openaerialmap/uploader-api`, private package),
image `:main` with `pullPolicy: Always`. Because the tag is mutable, ArgoCD sees
no diff when a new `:main` is pushed - a chart version bump is what rolls the
pods. Remaining release steps: `../../../oam-release.md`.

Databases are CNPG clusters in the `postgres` namespace, both committed:
`databases/oam-uploader-prod.yaml` (the uploader's own) and
`databases/oam-eoapi-pgstac-prod.yaml` (the catalog it registers into).
`db.enabled: false` here, so the chart's bundled Postgres never renders; staging
is the one that turns it on.

## Secrets

All four already exist. This section is for re-sealing, not bootstrap. Seal the
`oam` ones into `apps/oam/` (`../`), not this dir - the git source is
non-recursive, so a manifest in a component subdir is never applied.

**`oam-uploader-secrets`** (`../oam-uploader-secrets.yaml`), mounted with
`envFrom`. Three keys, no S3 credentials - those come from `oam-s3-creds` below.
`DB_PASSWORD` must match `oam-uploader-db-creds`, and `PGSTAC_DB_PASSWORD` the
pgstac cluster, which lives in another namespace so the value is duplicated here:

```bash
kubectl -n postgres get secret oam-eoapi-pgstac-prod-db-creds \
  -o go-template='{{range $k, $v := .data}}{{$k}}: {{$v | base64decode}}{{"\n"}}{{end}}'

kubectl create secret generic oam-uploader-secrets \
  --from-literal=COOKIE_SECRET=(openssl rand -hex 32) \
  --from-literal=DB_PASSWORD="xxx" \
  --from-literal=PGSTAC_DB_PASSWORD="xxx" \
  --namespace=oam --dry-run=client -o yaml \
  | kubeseal -o yaml > ../oam-uploader-secrets.yaml
```

**`oam-s3-creds`** (`../oam-s3-creds.yaml`) is the chart default and is shared
with `mosaic-cronjob` and `tilepack-api`. The chart reads it by key
(`secretKeyRef`, not `envFrom`), so HOTOSM's `S3_ACCESS_KEY`/`S3_SECRET_KEY`
naming is used as-is and the app still sees `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`:

```yaml
s3Secret:
  name: oam-s3-creds
  accessKeyIdKey: S3_ACCESS_KEY
  secretAccessKeyKey: S3_SECRET_KEY
```

That IAM user needs read **and** write on `oin-hotosm-temp`; the mosaic cronjob
that shares it only needs read, so it is worth confirming after any rotation.

**`argo-logs-s3-creds`** (`../argo-logs-s3-creds.yaml`). ScaleODM's controller
sets `artifactRepository.archiveLogs: true` with
`accessKeySecret.name: argo-logs-s3-creds`, and Argo resolves that
SecretKeySelector in the **workflow's** namespace, not the controller's
([docs](https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/)).
`archiveLogs` is on globally, so every namespace that runs workflows needs its
own copy - `odm`, `oam` and `oam-staging` each have one.

**`oam-uploader-db-creds`** (`../../../databases/oam-uploader-db-creds.yaml`) is
the CNPG bootstrap credential, in the `postgres` namespace and typed
`kubernetes.io/basic-auth`.

## Smoke test

```bash
kubectl -n oam run curl-test --rm -it --restart=Never \
  --image=curlimages/curl \
  --command -- curl -v http://uploader-api.oam.svc.cluster.local:8080/__lbheartbeat__
```

Then upload a small GeoTIFF at <https://upload.imagery.hotosm.org> and watch
`kubectl -n oam get workflows` until it reports Succeeded.
