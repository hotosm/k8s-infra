# Cluster Backups

- Most of our application state is backed up by ArgoCD / GitOps.
- All except:
  - The SealedSecrets master key.
  - Persistent volumes / storage.

## 1. Sealed Secret Master Key

- Restore the backed up master key secret:

```bash
kubectl apply -f main.yaml
```

## 2. ArgoCD (Apps)

To restore the ArgoCD setup:

- Go to `kubernetes/argocd-bootstrap` and follow the instructions
  to install ArgoCD and the root app.
- To force sync all the apps, run:

```bash
argocd app sync --all
```

## 3. Velero (Storage)

- Velero can backup cluster state for migration, but we only use
  it to backup storage volumes.
- To test this, backup and run on local TalosOS cluster.

### Pre-requisite

- Under `apps/velero.yaml` in this repo, we install the server-side
  Velero components via GitOps.
- The Velero CLI is needed to run the following commands.

Install Velero (needed?):

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.13.0 \
  --bucket my-backup-bucket \
  --backup-location-config region=us-east-1 \
  --use-volume-snapshots=false \
  --use-restic \
  --secret-file ./credentials-velero
```

Create a backup:

```bash
velero backup create pv-only \
  --include-resources persistentvolumes,persistentvolumeclaims \
  --include-namespaces '*' \
  --use-restic \
  --wait
```

Check the backup:

```bash
velero backup describe pv-only --details
```

> [!IMPORTANT]
> Switch to the local TalosOS cluster now.

Install to TalosOS:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.13.0 \
  --bucket my-backup-bucket \
  --backup-location-config region=us-east-1 \
  --use-restic \
  --use-volume-snapshots=false \
  --secret-file ./credentials-velero
```

Check backup:

```bash
velero get backups
```

Restore from backup:

```bash
velero restore create --from-backup pv-only --wait

# Then check if success
kubectl get pods --all-namespaces
kubectl get pvc,pv --all-namespaces
```
