## hot-website staging

A PR opened on [hotosm/website](https://github.com/hotosm/website) with head
`staging` targeting `main` triggers the `hot-website-staging` ApplicationSet
(see `../hot-website.yaml`). Workloads land in the `staging-website`
namespace, reachable at `https://staging.website.hotosm.org`. Closing/merging
the PR tears the deploy down and the node scales to 0.

### Sealed secret

Django needs a `SECRET_KEY` in `hot-website-secret-env` (chart default) or
the web pod won't start. Bundled Postgres provides `DATABASE_URL`, so
`SECRET_KEY` is the only required key; other prod integrations can be
dummied.

Write a plaintext `secret.yaml` (don't commit):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: hot-website-secret-env
  namespace: staging-website
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
