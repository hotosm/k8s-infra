# Resetting Databases

Handle with care. This is primarily needed when restoring prod data
into an already-running CloudNativePG database (e.g. during migration
per <https://docs.drone.hotosm.org/dev/migrate-k8s>).

If the CNPG cluster is freshly installed, just restore directly.
Otherwise, use one of the options below.

## Option 1: Drop and recreate the database (preferred)

The CNPG cluster, PV, and secrets all stay intact.

### 1. Pause ArgoCD auto-sync

All apps have `selfHeal: true`, so ArgoCD will revert any manual scaling
within seconds. Disable auto-sync first via the ArgoCD CLI:

```bash
argocd app set drone-tm --sync-policy none
```

Or via the ArgoCD UI:

1. Open the `drone-tm` application.
2. Click **App Details** (top bar).
3. Under **Sync Policy**, click **Disable Auto-Sync**.
4. Confirm when prompted.

> **Note:** `kubectl patch` on the Application resource won't work here
> because the root-app also has `selfHeal: true` and will revert the
> Application spec back to what's in Git.

### 2. Scale down the application

```bash
kubectl scale deploy drone-tm-prod-backend drone-tm-prod-worker \
  -n drone --replicas=0
```

### 3. Drop and recreate the database

```bash
# Terminate active connections
kubectl exec -it dronetm-db-prod-1 -n postgres -- psql -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = 'drone_tm_prod' AND pid <> pg_backend_pid();
"

# Drop and recreate
kubectl exec -it dronetm-db-prod-1 -n postgres -- \
  psql -U postgres -c "DROP DATABASE drone_tm_prod;"
kubectl exec -it dronetm-db-prod-1 -n postgres -- \
  psql -U postgres -c "CREATE DATABASE drone_tm_prod OWNER drone_tm_prod_rw;"

# Reinstall required extensions
kubectl exec -it dronetm-db-prod-1 -n postgres -- \
  psql -U postgres -d drone_tm_prod -c "
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
  "
```

### 4. Restore your dump

Use `pg_restore` / `psql` to load the prod data into `drone_tm_prod`.

### 5. Scale the application back up

```bash
kubectl scale deploy drone-tm-prod-backend -n drone --replicas=3
kubectl scale deploy drone-tm-prod-worker -n drone --replicas=2
```

### 6. Re-enable ArgoCD auto-sync

```bash
argocd app set drone-tm --sync-policy automated --self-heal --auto-prune
```

Or via the UI: **App Details** → **Sync Policy** → **Enable Auto-Sync**,
then tick **Self Heal** and **Prune**.

## Option 2: Delete and redeploy via ArgoCD

Use this only if the CNPG cluster itself is broken or you need to change
the cluster spec in a way that requires a full recreate (e.g. bootstrap
recovery from S3).

1. Comment out the database manifest in `databases/dronetm-prod.yaml`
   and push. ArgoCD will prune the cluster resources.
2. Delete the PersistentVolume to clear old data.
3. Uncomment the manifest and push. ArgoCD recreates the cluster
   with a fresh PV.
4. Restore your dump as above.
