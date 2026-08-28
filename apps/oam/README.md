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

## Adding a third-party catalogue

Add the provider to `stac-ingester` first; each `sync-<provider>.yaml` runs its
`hotosm sync-<provider>` command from that image. Before the first sync, create
its Collection with `hotosm sync-collection --catalog=<Name>` (a temporary Job
copied from its CronJob works); otherwise its Items are orphaned. Repeat when
the upstream Collection changes.

Prefer a wide sync window because existing Items are skipped. Maxar filters
events by `event_info.json` date; Vantor filters Items by `published`. To update
existing metadata, `dump-<provider>` to NDJSON and run
`pypgstac load items --method upsert`.

Databases are not here: `databases/oam-eoapi-pgstac-prod.yaml` and
`databases/oam-uploader-prod.yaml`, both running in the `postgres` namespace.

Staging is a separate, fully self-contained stack in `oam-staging` with no
external databases - `apps/staging/oam.yaml` and `apps/staging/oam/README.md`.

Remaining release steps for both prod and staging: `../../oam-release.md`.
