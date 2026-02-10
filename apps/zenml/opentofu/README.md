# Configuring ZenML

- Requires a bit more setup past a Helm deploy.
- A lot is configured via command line, with secrets stored
  encrypted in the Postgres database.

## CLI Setup

```bash
# We must run in our patched version of zenml for this to work
docker run --rm -it --entrypoint=bash \
  -v $HOME/.config/zenml:/zenml/.zenconfig \
  ghcr.io/hotosm/zenml-postgres:0.93.2

zenml login https://zenml.ai.hotosm.org
```

While it's possible to configure everything manually via
CLI, it's much cleaner to use OpenTofu by following
[this guide](https://docs.zenml.io/stacks/deployment/deploy-a-cloud-stack-with-terraform)

## ZenML OpenTofu

```bash
tofu init -var-file=vars/production.tfvars
tofu validate -var-file=vars/production.tfvars
tofu plan -var-file=vars/production.tfvars
tofu apply -var-file=vars/production.tfvars --dry-run
```

### Credentials

- In order to configure components, we first need to configure secrets.
- This allows the components to be accessed by ZenML.

### Components

Components we need:

- **Orchestrator**: Kubernetes (managing pipelines)
- **Artifact Store**: S3 (final model artifacts)
- **Deployer**: Kubernetes (to run inference jobs, note 'Model Deployer' is deprecated in favour of this)
- **Container Registry**: Github (storing containers)
- **Step Operator**: Kubernetes (for specific GPU steps)
- **Experiment Tracker**: MLFlow (already in cluster, for tracking experiments / how you got a model) +- WandB (Weights & Biases)
- **Image Builder**: Kaniko via Kubernetes (for building container images as needed)
- **Model Registry**: MLFlow (already in cluster, for versioning and lineage of prod models) +- WandB (Weights & Biases)
- **Log Store**: OTEL (to store logs and traces for pipelines - connect Sentry for now)

We already have all the services we need running, but just need to
configure them within ZenML via OpenTofu.

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
