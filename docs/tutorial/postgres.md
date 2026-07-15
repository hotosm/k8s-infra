# CloudNativePG

## Renaming a database while keeping data

CNPG has no in-place rename. Bootstrap a new cluster from the old one's
barman archive, switch the app, drop the old. Example below renames
`zenml-db-prod` (mis-named, actually staging) to `zenml-db-staging`.

### 1. Freeze writes + flush WAL

```bash
kubectl scale deploy zenml -n zenml --replicas=0
kubectl cnpg backup zenml-db-prod -n postgres
kubectl exec -n postgres zenml-db-prod-1 -- \
  psql -U postgres -c "SELECT pg_switch_wal();"
```

### 2. Copy the S3 archive with both prefixes renamed

Barman lays out backups at `<destinationPath>/<serverName>/{base,wals}`,
so rename both prefixes in a single sync:

```bash
aws s3 sync \
  s3://hotosm-k8s-db-backup/zenml-db-prod/zenml-db-prod/ \
  s3://hotosm-k8s-db-backup/zenml-db-staging/zenml-db-staging/
```

The inner `backup.info` files still contain `server_name = zenml-db-prod`
after the copy. Barman-cloud restore doesn't strictly validate that
field so recovery works, but the historical entries have inconsistent
metadata. Fully clean state comes from step 5 below — take a fresh
backup on the new cluster and prune the historical files.

### 3. Provision the new cluster

Create `databases/zenml-db-staging.yaml`:

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: zenml-db-staging-store
  namespace: postgres
spec:
  retentionPolicy: "60d"
  configuration:
    destinationPath: s3://hotosm-k8s-db-backup/zenml-db-staging
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
      source: zenml-db-prod-source
  externalClusters:
    - name: zenml-db-prod-source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: zenml-db-staging-store
          serverName: zenml-db-staging    # matches renamed prefix from step 2
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: zenml-db-staging-store
```

Also add a `zenml-db-staging-creds` sealed secret for the recovered primary.

### 4. Wait + verify data

```bash
kubectl get cluster zenml-db-staging -n postgres -w   # wait: In Healthy state
kubectl exec -n postgres zenml-db-staging-1 -- \
  psql -U postgres -c "SELECT count(*) FROM pipeline_run;"
# Compare row count against the old cluster.
```

### 5. Point the app at the new cluster

```yaml
zenml:
  database:
    url: "postgresql://zenml@zenml-db-staging-rw.postgres.svc.cluster.local:5432/zenml"
```

Commit, let ArgoCD sync, scale the app back up.

### 6. Take a fresh backup + prune historical archive

The historical `backup.info` files still say `server_name = zenml-db-prod`.
Take a fresh full backup so the archive has at least one entry authored
by `zenml-db-staging`, then prune the copied files.

```bash
kubectl cnpg backup zenml-db-staging -n postgres
kubectl get backup -n postgres -w   # wait: Completed

# Once you've verified the new backup restores cleanly, prune the copied
# historical files. Keep the new backup's base/ and any WAL segments
# created after the backup completed.
aws s3 ls s3://hotosm-k8s-db-backup/zenml-db-staging/zenml-db-staging/base/
# Delete every base/<id>/ dir that predates the fresh backup.
```

### 7. Drop the old cluster

```bash
kubectl delete cluster         zenml-db-prod         -n postgres
kubectl delete objectstore     zenml-db-prod-store   -n postgres
kubectl delete scheduledbackup zenml-db-prod-backup  -n postgres
kubectl delete sealedsecret    zenml-db-prod-creds   -n postgres
```

Also remove `databases/zenml-prod.yaml` and `databases/zenml-db-prod-creds.yaml`
from the repo. `s3://hotosm-k8s-db-backup/zenml-db-prod/` can be deleted
entirely — it's just the original source of the copy.

### Alternatives

- **Cold-clean:** skip recovery, provision empty, let migrations recreate schema.
- **Point-in-time:** add `bootstrap.recovery.recoveryTarget.targetTime`.
