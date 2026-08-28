# OpenAerialMap

One ArgoCD Application (`apps/oam.yaml`) deploys the whole stack into the `oam`
namespace.

| Component | Serves | Config |
|---|---|---|
| eoapi | api.imagery.hotosm.org (`/stac`, `/raster`, `/browser`) | `eoapi/helm/values.yaml`, see `eoapi/README.md` to migrate catalog data |
| stac-browser | `/browser` on the same host | `browser-ingress.yaml` (chart Ingress disabled) |
| stac-map | `/map` on the same host | `stac-map-deployment.yaml` |
| tilepack-api | tilepack downloads | `tilepack-api/helm/values.yaml` |
| global-tms | global PMTiles layer | chart defaults + `mosaic-cronjob.yaml` |
| uploader-api | upload.imagery.hotosm.org | `uploader-api/helm/values.yaml`, see `uploader-api/README.md` |
| ingest CronJobs | populate pgstac | `sync-oam.yaml`, `sync-maxar.yaml`, `sync-vantor.yaml` |

`browser-ingress.yaml` exists because of an upstream chart bug: on nginx,
`templates/networking/ingress.yaml` never honours `skipStripPrefix`, so
`/browser` gets `rewrite-target: /$2` and is stripped - but the image bakes
`SB_pathPrefix=/browser/` and 404s on `/`. The chart's Traefik template already
carries the flag. Upstream fix is to add `(not .skipStripPrefix)` to `$stripPath`
in `eoapi.ingressPaths` and flag the browser entry; then this file can go.

## Ingest CronJobs

| CronJob | Source | Schedule |
| --- | --- | --- |
| `stac-ingest-oam` | legacy openaerialmap.org API | every 30 min |
| `stac-ingest-maxar` | Maxar open data | daily |
| `stac-ingest-vantor` | Vantor open data | daily |

All three run the `stac-ingester` image, which is built from
[hotosm/openaerialmap](https://github.com/hotosm/openaerialmap/tree/main/backend/stac-ingester)
and tracks `main`.

How the windows behave, and what to do when imagery is missing, is documented
once in the OAM docs:

- [Ingestion overview](https://docs.imagery.hotosm.org/dev/ingest/)
- [Backfill](https://docs.imagery.hotosm.org/dev/ingest/backfill/)
- [Add a data provider](https://docs.imagery.hotosm.org/dev/ingest/new-provider/)

### Adding a catalogue

1. Merge the provider to `openaerialmap` `main`, so the image has it.
2. Add `sync-<provider>.yaml` here, copying `sync-vantor.yaml`.
3. Create its Collection once, or every Item lands orphaned:

```bash
kubectl -n oam create job vantor-collection --from=cronjob/stac-ingest-vantor \
  --dry-run=client --output yaml > job.yaml
# swap the `hotosm sync-vantor ...` line for `hotosm sync-collection --catalog=Vantor`
kubectl create -f job.yaml
kubectl -n oam logs -f job/vantor-collection
kubectl -n oam delete job vantor-collection
```

It upserts, so repeat it whenever the upstream Collection changes.

Databases are not here: `databases/oam-eoapi-pgstac-prod.yaml` and
`databases/oam-uploader-prod.yaml`, both running in the `postgres` namespace.

Staging is a separate, fully self-contained stack in `oam-staging` with no
external databases - `apps/staging/oam.yaml` and `apps/staging/oam/README.md`.

Remaining release steps for both prod and staging: `../../oam-release.md`.
