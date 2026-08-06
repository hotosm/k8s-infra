# A Simple Workflow Manager

- We can run many internal workflows via a simpler UI:
  - HDX Exports
  - Push announcement banner content for hotosm/ui integrated tools.
  - Data export and upload to uMap.
- A based on simple Python scripts to injectable variables.

## Creating the necessary secret

```bash
kubectl create secret generic windmill-db-url \
    --from-literal=url='postgresql://windmill:PASSWORD_HERE@windmill-db-rw.postgres.svc.cluster.local:5432/windmill' \
    --dry-run=client \
    --namespace='windmill' \
    -o yaml > secret.yaml

kubeseal -f secret.yaml -w windmill-db-url.yaml
```

## Autoscaled worker tags (manual step)

The autoscaled worker groups in `helm/values.yaml` (`osm-export-small`,
`osm-export-medium`, `osm-export-big`) each register a tag via `WORKER_TAGS`,
and KEDA scales them 0..N from the Postgres job queue (see `scaledobject.yaml`).

The worker side is fully managed by ArgoCD, but making a tag **selectable** on a
script/flow is not - it must be added once to Windmill's **Assignable Tags**
list, which lives in the Windmill database rather than these manifests:

1. Log in as a superadmin.
2. Go to the **Workers** tab and click **Assignable Tags**.
3. Add `osm-export-small`, `osm-export-medium`, `osm-export-big`
   (add `tm-export` once https://github.com/hotosm/k8s-infra/issues/184 lands).

Once a tag is assigned to a script/flow, scale-to-zero is fine: the job is
queued with its tag, KEDA counts it, and a worker is scaled up to run it.
