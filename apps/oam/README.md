# OpenAerialMap

One ArgoCD Application (`apps/oam.yaml`) deploys the whole stack into the `oam`
namespace.

| Component | Serves | Config |
|---|---|---|
| eoapi | api.imagery.hotosm.org (`/stac`, `/raster`, `/browser`) | `eoapi/helm/values.yaml`, see `eoapi/README.md` to migrate catalog data |
| stac-map | `/map` on the same host | `stac-map-deployment.yaml` |
| tilepack-api | tilepack downloads | `tilepack-api/helm/values.yaml` |
| global-tms | global PMTiles layer | chart defaults + `mosaic-cronjob.yaml` |
| uploader-api | upload.imagery.hotosm.org | `uploader-api/` - commented out in `apps/oam.yaml` |
| ingest CronJobs | populate pgstac | `sync-oam.yaml`, `sync-maxar.yaml` |

Databases are not here: `databases/oam-eoapi-pgstac-prod.yaml` and
`databases/oam-uploader-prod.yaml`, both running in the `postgres` namespace.
