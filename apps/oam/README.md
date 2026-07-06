# OpenAerialMap

Currently holds only the STAC ingest CronJobs (sync-maxar, sync-oam) that
populate the pgstac database used by eoAPI.

> [!NOTE]
> The eoAPI chart itself is still deployed via helmfile from
> `kubernetes/helm/`. Once it is migrated to an ArgoCD `Application`, that
> deploy should live here too so the whole OAM stack is managed from one dir.
