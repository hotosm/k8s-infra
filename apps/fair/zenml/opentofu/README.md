# ZenML stack (OpenTofu)

OpenTofu manages the ZenML stack, its S3 buckets and IAM, for both environments.
The config is identical in each OpenTofu dir, apart from `vars/`. Keep it that way:
change one, copy it to the other.

Re-apply after any change. The live stack doesn't follow git.

> [!NOTE]
> Run everything in
> [fair-cli](https://github.com/hotosm/fAIr/tree/develop/infra/zenml#using-zenml-cli),
> from the k8s-infra root, in one shell. Commands work in bash or fish.
> Env names are in the [environments table](../../README.md#environments).

## 1. Log in

Staging:

```sh
aws sso login --profile admin --use-device-code
export AWS_PROFILE=admin
export TF_VAR_mlflow_tracking_uri=http://mlflow.fair-staging.svc.cluster.local:5000
export TF_VAR_mlflow_tracking_username="$(kubectl -n fair-staging get secret mlflow-admin-password -o jsonpath='{.data.adminUsername}' | base64 -d)"
export TF_VAR_mlflow_tracking_password="$(kubectl -n fair-staging get secret mlflow-admin-password -o jsonpath='{.data.adminPassword}' | base64 -d)"
zenml login https://zenml.stage.ai.hotosm.org
cd apps/staging/fair/zenml/opentofu
```

Production (the MLflow URI and username are set in `vars/production.tfvars`):

```sh
aws sso login --profile admin --use-device-code
export AWS_PROFILE=admin
export TF_VAR_mlflow_tracking_password="$(kubectl -n fair-prod get secret mlflow-prod-admin-password -o jsonpath='{.data.adminPassword}' | base64 -d)"
zenml login https://zenml.ai.hotosm.org
cd apps/fair/zenml/opentofu
```

## 2. Get a ZenML API key

OpenTofu authenticates as the `opentofu` service account. Key values are only shown
once, so make a short-lived key each time:

```sh
zenml service-account create opentofu --create-api-key false # first time only
zenml service-account api-key opentofu create tofu --output-file /tmp/tofu-key
export ZENML_API_KEY="$(cat /tmp/tofu-key)" && rm /tmp/tofu-key
```

## 3. Plan and apply

Use `staging` or `production` for `<env>`. Every tofu command needs `-var-file`.

```sh
tofu init -var-file=vars/<env>.tfvars
tofu plan -var-file=vars/<env>.tfvars -out=tfplan
```

Read the plan before applying. Stop if it replaces buckets, IAM users or roles.

```sh
tofu apply tfplan && rm tfplan
tofu output -var-file=vars/<env>.tfvars -raw stack_id
zenml artifact-store describe s3-<env> # path should be s3://hotosm-fair-models-<env>/backend/zenml
zenml service-account api-key opentofu list # then delete the tofu key by ID
zenml service-account api-key opentofu delete <key id> -y
```

## 4. Roll out

1. If `stack_id` changed, set `ZENML_ACTIVE_STACK_ID` in the env's
   `backend/helm/values.yaml`.
2. If the plan created new backend AWS keys, reseal them (see
   [backend secrets](../../README.md#aws-keys)).
3. Commit, including `.terraform.lock.hcl`, and let Argo CD sync. Staging reads
   k8s-infra `main`.
4. Restart the backend, then test: `just test e2e` (staging), or [TESTING.md](../../TESTING.md).

## Fixing drift

> [!WARNING]
> If `tofu init` says `Backend configuration changed`, the `-var-file` was missing.
> Don't run `-reconfigure`, just re-run with the var file.

If the plan wants to create `aws_s3_bucket.data_stores[...]`, the bucket exists but isn't
in state. Import it, then plan again:

```sh
tofu import -var-file=vars/<env>.tfvars \
  'aws_s3_bucket.data_stores["hotosm-fair-models-<env>"]' hotosm-fair-models-<env>
```

If the plan wants to create `zenml_stack.aws_stack`, someone made the live stack by hand.
Move it aside so it keeps working until the backend switches over, and make OpenTofu
forget anything the old stack may still use that the plan would delete (connectors, their
IAM policies), so you can roll back. Clean them up later instead:

```sh
zenml stack rename k8s-<env> k8s-<env>-old
tofu state rm -var-file=vars/<env>.tfvars <resources the plan would destroy>
tofu plan -var-file=vars/<env>.tfvars -out=tfplan
```

Once the backend runs on the new stack and the test passes, remove the old one:

```sh
zenml stack delete k8s-<env>-old --recursive
zenml service-connector list # delete any old ones, keep aws-<env>
# and delete any IAM policies you removed from state, with aws iam delete-role-policy
```
