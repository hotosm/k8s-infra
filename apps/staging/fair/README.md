# fair staging (backend + eoAPI + MLflow + ZenML)

A PR opened on [hotosm/fAIr](https://github.com/hotosm/fAIr) with head
`staging` targeting `main` triggers the `fair-staging` ApplicationSet
(see `../fair.yaml`). All four services land in the `fair-staging`
namespace:

| Service      | Chart source                          | Values                        |
|--------------|---------------------------------------|-------------------------------|
| fair backend | `hotosm/fAIr` chart at PR `head_sha`  | `backend/helm/values.yaml`    |
| eoAPI (STAC) | `devseed/eoapi-k8s` 0.12.2            | `eoapi/helm/values.yaml`      |
| MLflow       | `community-charts/mlflow` 1.8.1       | `mlflow/helm/values.yaml`     |
| ZenML        | `oci://.../zenml/zenml` 0.94.2        | `zenml/helm/values.yaml`      |

Closing/merging the PR tears the four Helm workloads down; namespace,
quota/limits, sealed secrets, and ZenML pipeline RBAC persist
(`Prune=false,Delete=false`) so the next PR lands cleanly.

## Persistent state (survives PR churn)

- **Databases:** CNPG clusters `mlflow-db`, `zenml-db`, `fair-stac` in
  the `postgres` namespace. Not managed by this ApplicationSet.
- **MLflow artifacts:** S3 bucket `hotosm-fair-mlflow`.
- **STAC catalog data:** in `fair-stac` CNPG cluster.
- **fair backend DB:** ephemeral, bundled in the chart (`postgres.enabled: true`).
  Fresh Postgres per PR - this is intentional for clean backend testing.
