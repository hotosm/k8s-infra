# CloudNativePG

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
  psql -U postgres -c "SELECT count(*) FROM pipeline_run;"
```

### 4. Cutover

Writes to prod between step 1 and now won't reach the new cluster -
use [replica cluster mode][cnpg-replica] if that matters.

[cnpg-replica]: https://cloudnative-pg.io/documentation/current/replica_cluster/

```bash
kubectl scale deploy zenml -n zenml --replicas=0
```

Update `apps/zenml/helm/values.yaml`:

```yaml
zenml:
  database:
    url: "postgresql://zenml@zenml-db-staging-rw.postgres.svc.cluster.local:5432/zenml"
```

Commit, ArgoCD sync, scale the app back up. Add a `ScheduledBackup`
targeting `zenml-db-staging`.

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
