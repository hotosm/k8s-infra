## hot-website staging

A PR opened on [hotosm/website](https://github.com/hotosm/website) with head
`staging` targeting `main` triggers the `hot-website-staging` ApplicationSet
(see `../hot-website.yaml`). Workloads land in the `website-staging`
namespace, reachable at `https://staging.website.hotosm.org`. Closing/merging
the PR tears the Helm-managed workload down and the node scales to 0; the
namespace, quota/limits, and sealed secret persist so the next PR lands
cleanly without re-creating them.

### Sealed secret

Required to update:
- `SECRET_KEY`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Write a plaintext `secret.yaml` (don't commit):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hot-website-secret-env
  namespace: website-staging
type: Opaque
stringData:
  SECRET_KEY: "<random-string>"
  MAPBOX_ACCESS_TOKEN: "staging-placeholder"
  DEEPL_KEY: "staging-placeholder"
  SENTRY_DSN: ""
  AWS_STORAGE_BUCKET_NAME: "hotosm-website-staging"
  AWS_ACCESS_KEY_ID: "xxx"
  AWS_SECRET_ACCESS_KEY: "xxx"
  AWS_S3_REGION_NAME: "us-east-1"
```

Seal and commit:

```bash
kubeseal -f secret.yaml -w sealed-secret.yaml
```

### Copy production data

1. Copy the production DB --> staging DB.

```bash
# From the hotosm/website repo
# IMPORTANT: Ensure you are connected to the prod k8s cluster
just db-refresh-staging
```

2. Copy the S3 content prod --> staging:

```bash
aws s3 cp s3://hotosm-website s3://hotosm-website-staging --recursive --profile admin
```
