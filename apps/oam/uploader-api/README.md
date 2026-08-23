# OAM Uploader API

Imagery uploader at <https://upload.imagery.hotosm.org>. Uploads go presigned
direct-to-S3, then run as Argo Workflows (validate → COG → metadata → STAC
register), executed by the cluster-wide Argo controller from ScaleODM.

Deployed by the `uploader-api` sources in `apps/oam.yaml` (chart **0.2.0** from
GHCR, image `:main`). Publish 0.2.0 from openaerialmap `main` before the first
sync. It changes nothing prod exercises - the bundled-Postgres hardening is
behind `db.enabled`, which prod leaves off - so the app code being deployed is
just whatever `:main` already is.

## Prerequisites

The uploader's own database is not in this repo yet:
`databases/oam-uploader-prod.yaml` (CNPG cluster `oam-uploader-db`) is written
but **uncommitted**, and its bootstrap secret does not exist. Commit it together
with `oam-uploader-db-creds` below - the `databases` Application auto-syncs, and
`DB_HOST: oam-uploader-db-rw.postgres.svc` in `helm/values.yaml` has nothing to
resolve to until the cluster is up.

The pgstac catalog (`oam-eoapi-pgstac-prod-db-rw.postgres.svc`) is already
running, so nothing to do there beyond copying its password below.

## Secrets (one-time bootstrap)

Four secrets: three in `oam`, one in `postgres`. Seal the `oam` ones into
`apps/oam/` (`../`), not this dir - the git source is non-recursive, so a
manifest in a component subdir is never applied.

The existing `oam-s3-creds` cannot be reused yet: it keys its values as
`S3_ACCESS_KEY`/`S3_SECRET_KEY`, and chart 0.2.0 mounts credentials with
`envFrom`, which cannot rename keys - the app and the pipeline steps both read
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. The same IAM user is fine though;
pull its values out of the live secret and re-seal them under the right names:

```bash
kubectl -n oam get secret oam-s3-creds \
  -o go-template='{{range $k, $v := .data}}{{$k}}: {{$v | base64decode}}{{"\n"}}{{end}}'
```

That user needs read/write on `oin-hotosm-temp` - worth checking, since the
mosaic cronjob that shares it may only require read. Folding these two secrets
into one is a follow-up, see `migrating-eoapi.md`.

`PGSTAC_DB_PASSWORD` must match the pgstac cluster; the uploader is in a
different namespace to that secret, so the password is duplicated here:

```bash
kubectl -n oam get secret oam-eoapi-pgstac-prod-db-creds \
  -o go-template='{{range $k, $v := .data}}{{$k}}: {{$v | base64decode}}{{"\n"}}{{end}}'
```

App env - `DB_PASSWORD` must match `oam-uploader-db-creds` below:

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

The chart default S3 credentials come from `../oam-s3-creds.yaml`, which already
exist and are already read by mosaic-cronjob and tilepack-api:

```yaml
s3Secret:
  name: oam-s3-creds
  accessKeyIdKey: S3_ACCESS_KEY
  secretAccessKeyKey: S3_SECRET_KEY
```

Workflow log archiving. ScaleODM's controller sets `artifactRepository.archiveLogs:
true` with `accessKeySecret.name: argo-logs-s3-creds`
(`apps/scaleodm/helm/values.yaml`), and Argo resolves that SecretKeySelector in
the **workflow's** namespace, not the controller's: "The secrets are retrieved
from the namespace you use to run your workflows."
(<https://argo-workflows.readthedocs.io/en/latest/configure-artifact-repository/>).
The existing copy is namespaced `odm` - the workflow namespace - and there is no
copy in `argo` at all, which is the same conclusion from the other direction.
Since `archiveLogs` is on globally, every namespace running workflows needs one.
So re-seal the `odm` copy for `oam`:

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
