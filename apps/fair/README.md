# fAIr

fAIr runs as two environments on the HOT cluster. Production config lives here in
`apps/fair`. Staging config is in `apps/staging/fair`, and is deployed per PR (see the
[staging README](../staging/fair/README.md)).

Other guides:

- [ZenML stack (OpenTofu)](zenml/opentofu/README.md): apply infra changes.
- [TESTING.md](TESTING.md): manual end-to-end test.
- [fair-cli](https://github.com/hotosm/fAIr/tree/develop/infra/zenml#using-zenml-cli):
  the container with all the tools needed (zenml, tofu, aws, kubectl, kubeseal).

## Environments

This is the one place for names that differ between environments.

| | Staging | Production |
| --- | --- | --- |
| Frontend | https://stage.ai.hotosm.org | https://ai.hotosm.org |
| API | https://stage.ai.hotosm.org/api/v1 | https://api.ai.hotosm.org/api/v1 |
| STAC | https://stac.stage.ai.hotosm.org/stac | https://stac.ai.hotosm.org/stac |
| ZenML | https://zenml.stage.ai.hotosm.org | https://zenml.ai.hotosm.org |
| MLflow | no ingress, use `svc/mlflow` | https://mlflow.ai.hotosm.org |
| Model API | `https://staging-<model>.predict.ai.hotosm.org` | `https://<model>.predict.ai.hotosm.org` |
| Argo CD app | `fair-staging-pr-<n>` | `fair-production` |
| Namespace | `fair-staging` | `fair-prod` |
| Pipeline namespace | `zenml-pipelines-stage` | `zenml-pipelines-prod` |
| Backend deployment | `fair-backend` | `fair-backend-backend` |
| Reconcile CronJob | `fair-backend-knative-reconcile` | `fair-backend-backend-knative-reconcile` |
| Backend DB | bundled, fresh per PR | CNPG |
| pgstac secret | `fair-stac-db-creds` | `fair-stac-prod-db-creds` |
| MLflow admin secret | `mlflow-admin-password` | `mlflow-prod-admin-password` |
| Models bucket | `hotosm-fair-models-staging` | `hotosm-fair-models-production` |
| Backend IAM user | `fair-backend-staging` | `fair-backend-production` |
| ZenML stack | `k8s-staging` | `k8s-production` |
| OpenTofu dir | `apps/staging/fair/zenml/opentofu` | `apps/fair/zenml/opentofu` |

Shared by both:

- Model services run in `fair-knative`. Staging only serves them under the `staging`
  Knative tag, so it never moves production traffic.
- Model files are private in S3. The backend serves them through
  `/api/v1/artifacts/`, which only allows `<models bucket>/backend/zenml/`.
- STAC is read-only over HTTP. The backend writes to pgstac directly (`FAIR_STAC_DSN`).
- The eoapi chart sets the pgstac version. On a chart bump, match pypgstac in
  `fAIr/backend/uv.lock` and the `pgstac-pypgstac` tag in `fAIr/docker-compose.yml`.
  Migrations are one-way, so go staging first.

## Backend secrets

The backend reads everything from the `fair-api-credentials` sealed secret. Commands are
for production. For staging, swap the namespace, secret names and file path using the
table above (`apps/staging/fair/fair-api-credentials.yaml`).

> [!NOTE]
> Always pass `--format yaml` to `kubeseal --merge-into`, or it rewrites the file as JSON.
> Restart the backend after any change, as env vars are only read on start.

### AWS keys

Created by OpenTofu (`fair-backend-<env>` user). Reseal after the keys change:

```sh
TF_DIR=apps/fair/zenml/opentofu
kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal=AWS_ACCESS_KEY_ID="$(tofu -chdir=$TF_DIR output -var-file=vars/production.tfvars -raw fair_backend_aws_access_key_id)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(tofu -chdir=$TF_DIR output -var-file=vars/production.tfvars -raw fair_backend_aws_secret_access_key)" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml
```

### ZenML key

The backend uses an API key of a ZenML service account (`fair-backend` on production).
Key values are only shown once, so make a new one when needed, and delete the old one
after the backend restarts:

```sh
zenml login https://zenml.ai.hotosm.org
zenml service-account create fair-backend --create-api-key false # first time only
zenml service-account api-key fair-backend create backend-$(date +%Y%m%d) --output-file /tmp/key
kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal=ZENML_STORE_API_KEY="$(cat /tmp/key)" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml
rm /tmp/key
```

### pgstac DSN

```sh
kubectl -n fair-prod get secret fair-stac-prod-db-creds -o json | python3 -c '
import base64, json, sys
from urllib.parse import quote
d = {k: base64.b64decode(v).decode() for k, v in json.load(sys.stdin)["data"].items()}
print("postgresql://%s:%s@%s:%s/%s" % (quote(d["username"], safe=""),
    quote(d["password"], safe=""), d["host"], d["port"], d["database"]))' > /tmp/dsn
kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal=FAIR_STAC_DSN="$(cat /tmp/dsn)" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml
rm /tmp/dsn
```

### Login service keys

`LOGIN_INTERNAL_API_KEY` and `COOKIE_SECRET` must match the login service. Compare
hashes, then copy over any that differ:

```sh
for key in LOGIN_INTERNAL_API_KEY COOKIE_SECRET; do
  echo $key
  kubectl -n fair-prod get secret fair-api-credentials -o "jsonpath={.data.$key}" | base64 -d | sha256sum
  kubectl -n login get secret login-backend-secrets -o "jsonpath={.data.$key}" | base64 -d | sha256sum
done

key=LOGIN_INTERNAL_API_KEY # or COOKIE_SECRET
kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal="$key=$(kubectl -n login get secret login-backend-secrets -o "jsonpath={.data.$key}" | base64 -d)" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml
```

## Deploy and check

Commit, let Argo CD sync, then:

```sh
kubectl -n fair-prod rollout restart deployment/fair-backend-backend
kubectl -n fair-prod rollout status deployment/fair-backend-backend
curl -fsS https://api.ai.hotosm.org/api/v1/health/ | jq
kubectl -n knative-serving get certificate fair-predict-wildcard-tls
```

`postgresql`, `s3`, `stac_api` and `zenml` should be `true`. The STAC collections are
only created on the first base model registration. Then run [TESTING.md](TESTING.md).

## AWS dependencies

| Component | Purpose | Config |
| --- | --- | --- |
| S3 buckets | Models, datasets, ZenML artifacts | `zenml/opentofu/s3.tf` |
| Backend IAM user | S3 access and presigned URLs | `zenml/opentofu/s3.tf`, `fair-api-credentials.yaml` |
| Pipeline IRSA | Pipeline pods' S3 access | `zenml/opentofu/s3.tf`, `zenml-orchestrator-role.yaml` |
| ZenML AWS connector | Artifact store access | `zenml/opentofu/main.tf` |
| Frontend deploy IRSA | S3 upload, CloudFront invalidation (production) | `backend/helm/values.yaml`, `terraform/fair_s3_frontend.tf` |
| Karpenter node pools | GPU training, CPU inference | `apps/karpenter/` |

> [!NOTE]
> For non-AWS S3 storage, set `AWS_ENDPOINT_URL`. Leave it unset on AWS, as it also
> overrides the STS endpoint.
