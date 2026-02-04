# Flyte Demo

The basic demo from the Flyte home page.

## How to run

1. [Connect to the cluster](https://hotosm.github.io/k8s-infra/usage/connecting-to-cluster/#configure-aws-cli)
2. Port forward Flyte (in different terminals, or using ` &` after the command):

```bash
kubectl port-forward svc/flyteconsole -n flyte 8082:80
kubectl port-forward svc/flyteadmin -n flyte 8083:80
```

3. Run the workflow:

```bash
uv sync

# Test locally
uv run pyflyte run main.py training_workflow

# Test on remote cluster
uv run pyflyte run --remote main.py training_workflow
```
