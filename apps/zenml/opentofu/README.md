# Configuring ZenML

- Requires a bit more setup past a Helm deploy.
- A lot is configured via command line, with secrets stored
  encrypted in the Postgres database.

## CLI Setup

```bash
# We must run in our patched version of zenml for this to work
docker run --rm -it --entrypoint=bash \
  -v $HOME/.config/zenml:/zenml/.zenconfig \
  ghcr.io/hotosm/zenml-postgres:0.94.1

zenml login https://zenml.ai.hotosm.org
```

While it's possible to configure everything manually via
CLI, it's much cleaner to use OpenTofu by following
[this guide](https://docs.zenml.io/stacks/deployment/deploy-a-cloud-stack-with-terraform)

## Prerequisites

Before running OpenTofu, a few things need to be in place.

### 1. AWS credentials

You need an active AWS session with permissions to create IAM
users/roles, S3 buckets, and IAM policies. OpenTofu creates:

- An IAM user (`zenml-<env>`) with an `AssumeRole` policy
- An IAM role (`zenml-<env>`) with S3 access, assumed by the IAM user
- An S3 artifacts bucket (`<account-id>-zenml-artifacts-<env>`)

Authenticate however you normally do (SSO, env vars, etc.):

```bash
# Example with SSO
aws sso login --profile admin
export AWS_PROFILE=admin
```

### 2. ZenML API key

The ZenML provider authenticates via API key. Create one from the
ZenML server, then export it:

```bash
# Via the CLI (inside the zenml container)
zenml api-key create opentofu --set-api-key

# Or export directly
export ZENML_API_KEY='xxx'
```

### 3. Pipeline namespace

OpenTofu configures components to run pipelines in a dedicated
namespace (`zenml-pipelines` by default, set via
`zenml_pipeline_namespace` variable). Create it if it doesn't exist:

```bash
kubectl create namespace zenml-pipelines
```

### 4. Sensitive variables

MLFlow and Sentry credentials are passed as OpenTofu variables.
Either set them in a `*.auto.tfvars` file (git-ignored) or pass
them at apply time:

```bash
export TF_VAR_mlflow_tracking_uri="http://mlflow.mlflow.svc.cluster.local:5000"
export TF_VAR_mlflow_tracking_username="admin"
export TF_VAR_mlflow_tracking_password="xxx"
# Sentry OTLP endpoint (not the DSN). The public key is the hex string before @ in the DSN.
export TF_VAR_sentry_endpoint="https://<org>.ingest.us.sentry.io/api/<project-id>/integration/otlp"
export TF_VAR_sentry_public_key="<public-key-from-dsn>"
```

## Applying OpenTofu

```bash
cd apps/zenml/opentofu

tofu init -var-file=vars/production.tfvars
tofu validate -var-file=vars/production.tfvars
tofu plan -var-file=vars/production.tfvars
tofu apply -var-file=vars/production.tfvars
```

### Service Connectors

- **AWS** (`iam-role`): S3 artifact store access via IAM user + assume role

Kubernetes components (orchestrator, step operator, image builder) use
`incluster = true` in their own config - no service connector needed.

### Components

All components are configured in `main.tf`:

- **Orchestrator**: Kubernetes, in-cluster (`zenml-pipelines` namespace)
- **Artifact Store**: S3
- **Container Registry**: GitHub (GHCR `ghcr.io/hotosm`)
- **Step Operator**: Kubernetes (for specific GPU steps)
- **Image Builder**: Kaniko via Kubernetes (builds container images in-cluster).
  Note: https://github.com/zenml-io/zenml/issues/4122
- **Experiment Tracker**: MLFlow (in-cluster)
- **Model Registry**: MLFlow (in-cluster)
- **Log Store**: OTEL (connected to Sentry)

> **Note**: A Deployer component (e.g. KServe, Seldon) is not yet
> configured. For now inference jobs run via the orchestrator.

## Stacks

- A stack is simply a combination of components configured together.
- Once we have all components registered, we can create a few stacks
  for different combinations of components:
  - Kubernetes: prod / stage will likely contain everything
  - Local development: perhaps we only include MLFlow, but run the
    pipelines on our local machine for testing.

## Projects

- In theory we can run multiple projects on our stacks.
- This could be something like:
  - fAIr prod --> k8s prod stack
  - fAIr stage --> k8s stage stack
  - fAIr dev --> local dev stack (+mlflow)
  - osm-tagger dev --> local dev stack (+mlflow)
  - another tool prod --> k8s prod stack
  - etc
