# OpenAerialMap staging

On-demand staging of the uploader flow at <https://upload.stage.imagery.hotosm.org>,
with its own STAC API at <https://api.stage.imagery.hotosm.org>. Driven by
`staging`->`main` PRs on hotosm/openaerialmap; see `../oam.yaml`.

Everything runs in `oam-staging`. No CNPG cluster, no shared prod database and no
AWS bucket, so a PR deploy cannot reach prod data and needs nothing provisioned
outside the cluster:

| Component | Where it comes from |
| --- | --- |
| uploader-api | its chart, from the PR commit, image `sha-<head_sha>` |
| uploader DB | the same chart, `db.enabled=true`, ephemeral |
| object store | the same chart, `s3.rustfs.enabled=true`, ephemeral PVC |
| bucket setup | the same chart, `bucket-init` hook, on every sync |
| catalogue seed | the same chart, `seed.enabled=true`, on every sync |
| pgstac | `pgstac.yaml`, single-pod `ghcr.io/stac-utils/pgstac`, ephemeral |
| eoAPI raster | upstream chart 0.15.0 |
| eoAPI stac | upstream chart, our `stac-api` image at `sha-<head_sha>` |
| eoAPI root landing page | upstream chart's `docServer`, so the bare host is not a 404 |
| tilepack-api + worker | its chart, from the PR commit, images `sha-<head_sha>` |
| frontend | `frontend/`, image `sha-<head_sha>`, config injected at runtime |
| GeoTIFF WorkflowTemplate | `backend/uploader-api/pipeline`, from the PR commit |
| GLO-30 elevation | `jobs/`, image `sha-<head_sha>`, PostSync hook on every sync |
| GeoTIFF step images | `sha-<head_sha>` |
| Argo controller | cluster-wide, from ScaleODM, watches this namespace |

Read-only from prod, so there is nothing to stage:

| Thing | Why |
| --- | --- |
| coverage PMTiles | `global-mosaic` output in `oin-hotosm-temp`, public GET |
| global TMS | third-party image, chart only; the landing page links prod's |
| STAC Browser | static SPA; prod's copy browses this catalogue via `/browser/external/api.stage.imagery.hotosm.org/stac` |
| STAC Map | static SPA; prod's copy browses this catalogue via `/map/?href=https://api.stage.imagery.hotosm.org/stac` |

Not deployed: `global-mosaic` and the `stac-ingester` CronJobs. The unsynced
`jobs/ingest-glo30.yaml` is a manual, Nepal-scoped test. See
`../../oam/README.md`.

Neither viewer needs deploying: both take a catalogue at runtime, and the
staging eoAPI ingress already sends `Access-Control-Allow-Origin: *` so prod's
copies can read this one cross-origin. `frontend/frontend.yaml` points
`VITE_STAC_BROWSER_URL` and `VITE_STAC_MAP_URL` at prod; the frontend builds the
steering links. The `/browser` row on the root landing page is a dead link here.

Hostnames, all under `imagery.hotosm.org` so external-dns already covers them:

| Host | Serves |
| --- | --- |
| `stage.imagery.hotosm.org` | frontend |
| `api.stage.imagery.hotosm.org` | eoAPI `/stac`, `/raster` and the root landing page |
| `upload.stage.imagery.hotosm.org` | uploader-api |
| `packager.stage.imagery.hotosm.org` | tilepack-api |
| `s3.stage.imagery.hotosm.org` | the object store's S3 API |

## Why not the eoAPI bundled database

The eoAPI chart's `postgrescluster` is the Crunchy pgo operator. HOTOSM
standardised on CNPG, so every eoAPI values file here sets
`postgrescluster.enabled: false` with `postgresql.type: external-secret` -
staging just points that at an in-namespace pod instead of a CNPG cluster.

`ghcr.io/stac-utils/pgstac` is the right pod for it because it bakes in
everything `databases/fair-stac.yaml` has to do by hand in
`postInitApplicationSQL`: postgis/btree_gist/unaccent, the
`pgstac_admin`/`pgstac_read`/`pgstac_ingest` roles, a migrated pgstac schema,
and `search_path = pgstac, public`. That matters here because the chart's
`pgstacSuperuserInitDb` job only renders when `postgrescluster.enabled` - with
an external database the connecting user must already hold those grants. It is
also the image `compose.yaml` uses, so staging matches local dev.

Two traps in that image are handled in `pgstac.yaml`. Its initdb script calls
bare `psql`, so `PGUSER`/`PGPASSWORD`/`PGDATABASE` must be set or init dies with
`role "postgres" does not exist`. And it runs `ALTER SYSTEM` at initdb, sizing
`shared_buffers` and friends from `/proc/meminfo` - the **node's** memory, not
the pod limit - which lands on multi-GB values and an OOMKilled pod.
Command-line args outrank `postgresql.auto.conf`, so they are pinned there.

## One-time bootstrap

### 1. Branch and image builds

Create a `staging` branch on hotosm/openaerialmap. Every commit on it must build
all six images that the ApplicationSet pins at `sha-<head_sha>`, or the pods sit
in `ImagePullBackOff` - `.github/workflows/staging-images.yml` does that, with no
path filters, so a commit that touched only one component still tags the rest.

### 2. Object storage

Nothing to create. The uploader-api chart bundles a RustFS store
(`s3.rustfs.enabled=true`) at `s3.stage.imagery.hotosm.org`, and its
`bucket-init` hook creates the `oam-staging` bucket with a public-read policy and
CORS for `https://upload.stage.imagery.hotosm.org` on every sync.

The imagery lives on a PVC that goes when the PR closes, so teardown is the only
cleanup. Two things it rests on:

- **`gp3-ephemeral`, not `gp3`.** `reclaimPolicy: Delete`, so closing the PR
  releases the volume, not just the claim. ArgoCD ignores the
  `helm.sh/resource-policy: keep` the subchart puts on the PVC
  ([argo-cd#17819][]), which is what makes prune work here at all.
- **Storage is sized by hand.** 30Gi against `seed.maxGiB: 10` leaves ~20Gi for
  testers, and an upload costs roughly twice its size - the pipeline keeps both
  the original and its COG, and tilepacks land in the same bucket. `maxGiB` caps
  one run, not the bucket. Raise the seed without the volume and it fills
  mid-copy; the `ResourceQuota` caps CPU, memory and pods but not storage, so
  nothing else will stop you.

The S3 API is public because it has to be: the browser PUTs straight to it and
STAC asset hrefs are absolute. That second part is worth checking first on a new
deploy - eoAPI's raster pods fetch those hrefs by hostname, leaving the cluster
and coming back through the ingress load balancer. It works on EKS; if `/raster`
502s while `/stac` is fine, that hairpin is where to look.

[argo-cd#17819]: https://github.com/argoproj/argo-cd/issues/17819

### 3. Sealed secrets

Seal into this directory. The namespace must be `oam-staging`. `PGSTAC_DB_PASSWORD`
must match `oam-stac-db-creds` in `pgstac.yaml` (`oam_stac`); `DB_PASSWORD` is
not needed because the bundled DB injects its own.

```bash
kubectl create secret generic oam-uploader-staging-secrets \
  --from-literal=COOKIE_SECRET=(openssl rand -hex 32) \
  --from-literal=PGSTAC_DB_PASSWORD="oam_stac" \
  --namespace=oam-staging --dry-run=client -o yaml \
  | kubeseal -o yaml > oam-uploader-staging-secrets.yaml
```

S3 credentials, read by the app, tilepack-api and the WorkflowTemplate's aws-cli
steps. Same name and keys as prod's `apps/oam/oam-s3-creds.yaml`, so nothing has
to be configured per environment. No region key: the app takes `S3_REGION` and
the pipeline the `awsregion` workflow parameter.

These are the bundled store's credentials, not AWS: no IAM user to create and
nothing to scope, so any random keypair will do.

```bash
kubectl create secret generic oam-s3-creds \
  --from-literal=S3_ACCESS_KEY=(openssl rand -hex 16) \
  --from-literal=S3_SECRET_KEY=(openssl rand -hex 32) \
  --namespace=oam-staging --dry-run=client -o yaml \
  | kubeseal -o yaml > oam-s3-creds.yaml
```

Workflow log archiving - the artifact-repository secret is resolved in the
workflow's namespace, so re-seal the `odm` copy
(`apps/scaleodm/argo-logs-s3-creds.yaml`) for `oam-staging`:

```bash
kubectl create secret generic argo-logs-s3-creds \
  --from-literal=AWS_ACCESS_KEY_ID="xxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxx" \
  --namespace=oam-staging --dry-run=client -o yaml \
  | kubeseal -o yaml > argo-logs-s3-creds.yaml
```

Add `argocd.argoproj.io/sync-options: Prune=false,Delete=false` to each, as
`bootstrap.yaml` does, so PR teardown leaves them behind.

## Smoke test

```bash
kubectl -n oam-staging get pods
kubectl -n oam-staging logs job/eoapi-pgstac-migrate
# Creates the bucket, then copies up to 10GiB from prod into it. The
# ApplicationSet stays Progressing until the seed finishes.
kubectl -n oam-staging logs job/uploader-api-bucket-init
kubectl -n oam-staging logs -f job/uploader-api-seed

kubectl -n oam-staging run curl-test --rm -it --restart=Never \
  --image=curlimages/curl \
  --command -- curl -v http://uploader-api.oam-staging.svc.cluster.local:8080/__lbheartbeat__
```

Then upload a small GeoTIFF at <https://upload.stage.imagery.hotosm.org> and
watch `kubectl -n oam-staging get workflows` until it reports Succeeded.

## Teardown

Closing the PR deletes the Application; the resources-finalizer prunes the Helm
workloads, the pgstac pod and the store's PVC. The namespace, quota/limits and
sealed secrets carry `Prune=false,Delete=false` and persist, so the next PR lands
cleanly. Both databases are `emptyDir` and the imagery is on a `gp3-ephemeral`
volume, so nothing survives - the next deploy's `bucket-init` and seed hooks
rebuild the bucket and catalogue from prod.

Check the volume actually went; a leaked one bills quietly:

```bash
kubectl -n oam-staging get pvc
```
