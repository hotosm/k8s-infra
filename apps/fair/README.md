# fAIr production

Production mostly mirrors `apps/staging/fair`. The main differences are the
domains, databases, buckets and sealed secrets. Production also uses an external
CNPG database and serves the frontend through CloudFront.

| Service | URL |
| --- | --- |
| Frontend | https://ai.hotosm.org |
| API | https://api.ai.hotosm.org |
| STAC | https://stac.ai.hotosm.org/stac |
| ZenML | https://zenml.ai.hotosm.org |
| MLflow | https://mlflow.ai.hotosm.org |
| Model API | `https://<model>.predict.ai.hotosm.org/predict` |

The backend, eoAPI, MLflow and ZenML run in `fair-prod`. ZenML jobs run in
`zenml-pipelines-prod`. Model services run in the shared `fair-knative`
namespace.

STAC is read-only over HTTP. The backend writes directly to pgstac using
`FAIR_STAC_DSN`. Model artifacts are private in S3 and are served through the
backend's presigned URL endpoint.

## Configure production

Run these commands from the repository root. You will need `kubectl`, `aws`,
`kubeseal`, `tofu` and access to the production cluster and AWS account.

### 1. Check the cluster resources

In Argo CD, check that `fair-production`, `knative-serving`, `fair-knative-hub`
and `cluster-core` are synced and healthy.

```bash
kubectl get namespace zenml-pipelines-prod
kubectl -n zenml-pipelines-prod get serviceaccount,role,rolebinding
kubectl -n fair-prod get pods
```

The `fair-model-deployer` service account starts ZenML jobs. Job pods use
`zenml-pod-account`; their RBAC is in `zenml-orchestrator-role.yaml`.

### 2. Create the ZenML API keys

Use the patched ZenML image so the CLI matches the server:

```bash
docker run --rm -it --entrypoint=bash ghcr.io/hotosm/fair/zenml-postgres:0.94.2

# Run inside the container
zenml login https://zenml.ai.hotosm.org
zenml service-account create opentofu
zenml service-account create fair-backend
```

Each command prints its API key once. Use the `opentofu` key as
`ZENML_API_KEY` and the `fair-backend` key as `ZENML_STORE_API_KEY` below.

### 3. Apply the ZenML stack

Authenticate to the HOT AWS account, then plan the production stack:

```bash
aws sso login --profile admin
export AWS_PROFILE=admin
export AWS_REGION=us-east-1
aws sts get-caller-identity # account 670261699094

export ZENML_API_KEY='<opentofu API key>'
export TF_VAR_mlflow_tracking_username="$(
  kubectl -n fair-prod get secret mlflow-prod-admin-password \
    -o jsonpath='{.data.adminUsername}' | base64 -d
)"
export TF_VAR_mlflow_tracking_password="$(
  kubectl -n fair-prod get secret mlflow-prod-admin-password \
    -o jsonpath='{.data.adminPassword}' | base64 -d
)"

cd apps/fair/zenml/opentofu
tofu init -var-file=vars/production.tfvars
tofu validate
tofu plan -var-file=vars/production.tfvars -out=tfplan
tofu apply tfplan
tofu output -raw stack_id
rm tfplan
cd ../../../..
```

The production state is stored in
`s3://hotosm-terraform/production/zenml-prod/`. Before applying, check that the
existing buckets are still in state:

```bash
tofu -chdir=apps/fair/zenml/opentofu state list | grep -E 'data_stores|artifacts'
```

If the models bucket is missing, import it rather than creating a replacement:

```bash
tofu -chdir=apps/fair/zenml/opentofu import \
  -var-file=vars/production.tfvars \
  'aws_s3_bucket.data_stores["hotosm-fair-models-production"]' \
  hotosm-fair-models-production
```

Set `ZENML_ACTIVE_STACK_ID` in `backend/helm/values.yaml` to the new `stack_id`.
Commit `.terraform.lock.hcl` if it changes; do not commit `.terraform/` or a
saved plan.

### 4. Seal the backend credentials

`LOGIN_INTERNAL_API_KEY` and `COOKIE_SECRET` must match the values used by the
login service. This prints hashes only:

```bash
for key in LOGIN_INTERNAL_API_KEY COOKIE_SECRET; do
  echo "$key"
  kubectl -n fair-prod get secret fair-api-credentials \
    -o "jsonpath={.data.$key}" | base64 -d | sha256sum
  kubectl -n login get secret login-backend-secrets \
    -o "jsonpath={.data.$key}" | base64 -d | sha256sum
done
```

If a pair differs, copy and reseal that key:

```bash
key=LOGIN_INTERNAL_API_KEY # or COOKIE_SECRET
kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal="$key=$(kubectl -n login get secret login-backend-secrets \
    -o "jsonpath={.data.$key}" | base64 -d)" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml
```

Seal the AWS credentials created by OpenTofu, the pgstac DSN and the backend
ZenML key:

```bash
TF_DIR=apps/fair/zenml/opentofu
STAC_DSN="$(kubectl -n fair-prod get secret fair-stac-prod-db-creds -o json | \
  python3 -c '
import base64, json, sys
from urllib.parse import quote

d = {
    key: base64.b64decode(value).decode()
    for key, value in json.load(sys.stdin)["data"].items()
}
print("postgresql://%s:%s@%s:%s/%s" % (
    quote(d["username"], safe=""), quote(d["password"], safe=""),
    d["host"], d["port"], d["database"],
))
')"
read -rsp 'fair-backend ZenML API key: ' ZENML_STORE_API_KEY
echo

kubectl create secret generic fair-api-credentials -n fair-prod \
  --from-literal=AWS_ACCESS_KEY_ID="$(tofu -chdir="$TF_DIR" output -raw fair_backend_aws_access_key_id)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(tofu -chdir="$TF_DIR" output -raw fair_backend_aws_secret_access_key)" \
  --from-literal=FAIR_STAC_DSN="$STAC_DSN" \
  --from-literal=ZENML_STORE_API_KEY="$ZENML_STORE_API_KEY" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml --merge-into apps/fair/fair-api-credentials.yaml

unset STAC_DSN ZENML_STORE_API_KEY TF_VAR_mlflow_tracking_password ZENML_API_KEY
git diff -- apps/fair/fair-api-credentials.yaml
```

Always pass `--format yaml` when using `kubeseal --merge-into`; otherwise it may
rewrite the file as JSON.

### 5. Deploy and check

Commit the sealed secret and stack ID, then let Argo CD sync. Restart the backend
after a secret change because `envFrom` is only read when a pod starts.

```bash
kubectl -n fair-prod rollout restart deployment/fair-backend-backend
kubectl -n fair-prod rollout status deployment/fair-backend-backend
curl -fsS https://api.ai.hotosm.org/api/v1/health/ | jq
```

`postgresql`, `s3`, `stac_api` and `zenml` should be `true`. STAC collections
are created when the first base model is registered, so `stac_collections` may
be `false` on a new deployment.

Also check the prediction wildcard certificate and the read-only STAC endpoint:

```bash
kubectl -n knative-serving get certificate fair-predict-wildcard-tls
curl -o /dev/null -sS -w '%{http_code}\n' -X POST \
  -H 'content-type: application/json' -d '{}' \
  https://stac.ai.hotosm.org/stac/collections # 405
```

Finally, register the base models in the fAIr admin UI and run one training and
prediction job. Registering a model creates its STAC records and Knative
service. Staging shares these services under the `staging` traffic tag, so
production traffic only moves when a model is registered here. The
`knative-reconcile` CronJob re-applies services from STAC every 15 minutes.

```bash
kubectl -n fair-knative get ksvc
kubectl -n zenml-pipelines-prod get jobs,pods
curl -fsS https://stac.ai.hotosm.org/stac/collections | jq '.collections[].id'
```

## AWS dependencies

| Component | Purpose | Configuration |
| --- | --- | --- |
| Pipeline IRSA | Pipeline access to model and dataset S3 objects | `zenml-orchestrator-role.yaml`, `zenml/opentofu/s3.tf` |
| Frontend deploy IRSA | Production S3 upload and CloudFront invalidation | `backend/helm/values.yaml`, `terraform/frontend_s3_cloudfront.tf` |
| ZenML AWS connector | ZenML artifact-store access | `zenml/opentofu/main.tf` |
| Backend IAM user | S3 access and presigned URLs | `zenml/opentofu/s3.tf`, `fair-api-credentials.yaml` |
| S3 buckets | Models, datasets and ZenML artifacts | `zenml/opentofu/s3.tf` |
| Karpenter node pools | GPU training and CPU inference capacity | `apps/karpenter/` |

For non-AWS S3-compatible storage, set `AWS_ENDPOINT_URL`; leave it unset on
AWS because it also overrides the STS endpoint.
