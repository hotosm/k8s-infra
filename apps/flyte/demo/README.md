# Flyte Demo

The basic demo from the Flyte home page.

## How to run

1. [Connect to the cluster](https://hotosm.github.io/k8s-infra/usage/connecting-to-cluster/#configure-aws-cli)
2. Port forward Flyte (in different terminals, or using ` &` after the command):

```bash
# For task submission
kubectl port-forward service/flyte-flyte-binary-http -n flyte 8090:8090
```

3. Run the workflow:

```bash
uv sync

# Test locally
uv run flyte run --local main.py training_workflow

# Test on remote cluster
uv run python main.py
```
