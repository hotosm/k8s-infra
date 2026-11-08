# fAIr staging

Opening a PR on [hotosm/fAIr](https://github.com/hotosm/fAIr) from `staging` to `main`
deploys staging, via the `fair-staging` ApplicationSet (`../fair.yaml`). Closing or
merging the PR tears it down again.

Everything shared with production (names, secrets, the ZenML stack, testing) is in
[apps/fair/README.md](../../fair/README.md).

| Service | Chart | Values |
| --- | --- | --- |
| fAIr backend | `hotosm/fAIr` chart at the PR `head_sha` | `backend/helm/values.yaml` |
| eoAPI (STAC) | `devseed/eoapi-k8s` 0.16.4 | `eoapi/helm/values.yaml` |
| MLflow | `community-charts/mlflow` 1.8.1 | `mlflow/helm/values.yaml` |
| ZenML | `oci://.../zenml/zenml` 0.94.2 | `zenml/helm/values.yaml` |

## What survives between PRs

- The namespace, quotas, sealed secrets and ZenML pipeline RBAC
  (`Prune=false,Delete=false`).
- The MLflow, ZenML and STAC databases (CNPG clusters in `postgres`).
- MLflow artifacts, in the `hotosm-fair-mlflow` bucket.

The backend database is bundled and fresh for each PR, on purpose, so every test
starts clean. That also means you need to make yourself admin again on each PR
(`just test e2e` does this for you).
