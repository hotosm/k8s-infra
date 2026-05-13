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
