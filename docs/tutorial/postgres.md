# CloudNativePG

## Restoring a cluster from its S3 archive

Every `Cluster` in `databases/` bootstraps with `recovery`, not `initdb`:

```yaml
  bootstrap:
    recovery:
      source: fieldtm-db-prod
  externalClusters:
    - name: fieldtm-db-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: fieldtm-db-prod-store
          serverName: fieldtm-db-prod
```

`bootstrap` is read **only at Cluster creation**, so this is inert on a running
cluster. It matters on a rebuild, or after an accidental delete: ArgoCD applies
these manifests and each database restores instead of coming up empty. The
original `initdb` stays commented below it in each file.

> Never restore Postgres from Velero. It copies files from a live database, and
> `walStorage` is a separate PVC - so data and WAL come from different instants,
> which Postgres cannot reconcile. The S3 archive is the only restore path.

### serverName

Barman writes to `<destinationPath>/<serverName>/`, and `serverName` defaults to
the Cluster name. A restored cluster reads from that prefix and then wants to
write its own WAL there, so CNPG stops it at bootstrap with `Expected empty
archive`. That means recovery worked and the write target needs changing - bump
the archiver's `serverName`, leaving `externalClusters` on the old one:

```yaml
  externalClusters:
    - name: fieldtm-db-prod
      plugin:
        parameters:
          serverName: fieldtm-db-prod       # read: unchanged
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        serverName: fieldtm-db-prod-v2      # write: bumped
```

Both prefixes share one `ObjectStore`; drop the old one once the new cluster has
a successful `ScheduledBackup`. `mlflow-prod-db` already runs this way.

**Never bump `serverName` on a running cluster** - it starts an empty chain and
orphans every base backup, leaving it unrestorable until the next one completes.

A recovery that reports no backup found usually has the wrong `serverName`.
Check with `aws s3 ls s3://hotosm-k8s-db-backup/fieldtm-prod/`, then confirm the
new prefix archives with `bash scripts/verify-cnpg-backups.sh fieldtm-db-prod`.
To rehearse, recover into a scratch Cluster with its own `ObjectStore`, then
delete it.

## Renaming a cluster + its S3 archive

Renames `zenml-db-prod` → `zenml-db-staging`, archive prefix
`zenml-prod/` → `zenml-staging/`.

> Do **not** `aws s3 sync` the old archive to the new prefix. The new
> cluster's archive destination must be empty at bootstrap or the
> pre-flight check fails with `Expected empty archive`.

### 1. Backup prod

The cluster backs up via the barman-cloud plugin, so `kubectl cnpg backup`
fails (`cluster has no backup section`). Apply a plugin-method `Backup`
instead:

```bash
kubectl apply -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: zenml-db-prod-manual-preflip
  namespace: postgres
spec:
  cluster:
    name: zenml-db-prod
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF

kubectl get backup zenml-db-prod-manual-preflip -n postgres -w   # wait: Completed
```

### 2. Provision the new cluster

Ensure the destination is empty:

```bash
aws s3 rm --recursive s3://hotosm-k8s-db-backup/zenml-staging/
```

Add `zenml-db-staging-creds` sealed secret, then `databases/zenml-db-staging.yaml`:

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: zenml-db-staging-store
  namespace: postgres
spec:
  retentionPolicy: "60d"
  configuration:
    destinationPath: s3://hotosm-k8s-db-backup/zenml-staging
    endpointURL: https://s3.amazonaws.com
    s3Credentials:
      accessKeyId:     { name: s3-creds, key: access-key-id }
      secretAccessKey: { name: s3-creds, key: secret-access-key }
    wal:  { compression: gzip, encryption: AES256 }
    data: { compression: gzip, encryption: AES256, jobs: 2 }
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: zenml-db-staging
  namespace: postgres
spec:
  instances: 1
  imageName: "ghcr.io/cloudnative-pg/postgresql:18-system-trixie"
  storage:    { storageClass: gp3, size: 20Gi }
  walStorage: { storageClass: gp3, size: 40Gi }
  bootstrap:
    recovery:
      source: zenml-db-prod
  externalClusters:
    - name: zenml-db-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: zenml-db-prod-store
          serverName: zenml-db-prod
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: zenml-db-staging-store
```

Commit, let ArgoCD sync.

### 3. Verify

```bash
kubectl get cluster zenml-db-staging -n postgres -w   # In Healthy state
kubectl exec -n postgres zenml-db-staging-1 -- \
  psql -U postgres -d zenml -c "SELECT count(*) FROM pipeline_run;"
```

### 4. Switch

Once staging is `Healthy` and the counts match, point the app at it in
`apps/zenml/helm/values.yaml`:

```yaml
zenml:
  database:
    url: "postgresql://zenml@zenml-db-staging-rw.postgres.svc.cluster.local:5432/zenml"
```

Commit, let ArgoCD sync - the URL change rolls the Deployment, which
reconnects to the new DB (retrying until it's up). Then add a
`ScheduledBackup` targeting `zenml-db-staging`.

Writes to prod between step 1 and now won't reach the new cluster -
use [replica cluster mode][cnpg-replica] if that matters.

[cnpg-replica]: https://cloudnative-pg.io/documentation/current/replica_cluster/

### 5. Drop the old cluster + S3 archive

After one successful scheduled backup on the new cluster:

```bash
kubectl delete cluster         zenml-db-prod        -n postgres
kubectl delete objectstore     zenml-db-prod-store  -n postgres
kubectl delete scheduledbackup zenml-db-prod-backup -n postgres
kubectl delete sealedsecret    zenml-db-prod-creds  -n postgres
aws s3 rm --recursive s3://hotosm-k8s-db-backup/zenml-prod/
```

Remove `databases/zenml-prod.yaml` and `databases/zenml-db-prod-creds.yaml`.

## Verifying backups and WAL archiving

A successful base backup does not prove WAL archiving works, and a base backup
without its WAL is unrestorable. `scripts/verify-cnpg-backups.sh` checks both —
its header comment explains why status pages can read green while archiving is
completely broken.

```bash
bash scripts/verify-cnpg-backups.sh                  # audit every cluster
bash scripts/verify-cnpg-backups.sh mlflow-prod-db   # prove one really archives
```

Run it after provisioning a cluster, and after changing an `ObjectStore` or
`s3-creds`. On failure the S3 error is in the `plugin-barman-cloud` sidecar.

### Sizing note

WAL volume size is unrelated to database size — `pg_wal` recycles within
`max_wal_size`, so steady state is 1–3Gi. A WAL volume needing tens of
gigabytes is a retention failure (broken archiver, or an inactive replication
slot pinning segments), not a busy database.
