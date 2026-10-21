# ArgoCD Apps

- Configurations inside this directory are scanned by ArgoCD,
  and automatically deployed into the cluster.

Access Argo dashboard (on the tailnet): http://argocd

## Knative (fAIr model serving)

Three apps, in dependency order:

| App | Contains |
|---|---|
| `knative-operator` | Upstream chart: the operator plus its CRDs |
| `knative-serving` | `KnativeServing` CR - Kourier, HA replicas, the predict domain |
| `fair-knative` | Namespace, RBAC for `fair-model-deployer`, nginx->Kourier Ingress |

Request path:

`*.predict.ai.hotosm.org` -> nginx -> Kourier -> activator -> the model's
Knative Service in `fair-knative`.

Never manage the `config-domain` ConfigMap from git: the operator renders it
from the `KnativeServing` CR and the two will overwrite each other forever.
