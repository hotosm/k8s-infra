# tm-sandbox OSM Exporter

Daily CronJob that exports OSM data from `osm-db` (the sandbox OpenStreetMap database)
and uploads the PBF file to S3. Runs at **03:00 UTC** every day.

Output: `s3://tm-sandbox-extracts-670261699094-us-east-1-an/exports/YYYY-MM-DD/sandbox-export.pbf`

## Secret

All credentials (PostgreSQL + S3) live in a single sealed secret: `sandbox-osm-exporter-secrets`.

To recreate it:

```bash
kubectl create secret generic sandbox-osm-exporter-secrets \
  --namespace tm-sandbox \
  --from-literal=SRC_PGHOST=osm-db.tm-sandbox.svc.cluster.local \
  --from-literal=SRC_PGDATABASE=sandbox_db \
  --from-literal=SRC_PGUSER=postgres \
  --from-literal=SRC_PGPASSWORD=xxx \
  --from-literal=SRC_PGPORT=5432 \
  --from-literal=S3_ACCESS_KEY=xxx \
  --from-literal=S3_SECRET_KEY=xxx \
  --from-literal=S3_BUCKET=tm-sandbox-extracts-670261699094-us-east-1-an \
  --from-literal=S3_REGION=us-east-1 \
  --dry-run=client -o yaml > /tmp/sandbox-osm-exporter-secrets.yaml

kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  < /tmp/sandbox-osm-exporter-secrets.yaml \
  > apps/tm-sandbox/sealed-secret-sandbox-osm-exporter-secrets.yaml

rm /tmp/sandbox-osm-exporter-secrets.yaml
```

## Triggering manually

```bash
kubectl create job --from=cronjob/sandbox-osm-export manual-test -n tm-sandbox
kubectl logs -n tm-sandbox -l app=sandbox-osm-export --container osm-export -f
kubectl logs -n tm-sandbox -l app=sandbox-osm-export --container s3-uploader -f
kubectl delete job manual-test -n tm-sandbox
```
