# Monitoring: cluster-wide Prometheus + Grafana

One `kube-prometheus-stack` (Prometheus Operator, Prometheus, Alertmanager,
Grafana, node-exporter, kube-state-metrics) for the whole cluster (issue #134).
Apps opt in with a `ServiceMonitor`/`PodMonitor` in any namespace - the Operator
discovers and scrapes them; no per-app Prometheus.

## Required before first sync: Grafana admin secret

Grafana reads `grafana-admin-creds` (referenced in `helm/values.yaml`). Seal it
into the `monitoring` ns and commit it here so the `path: apps/monitoring` source
applies it:

```bash
kubectl create secret generic grafana-admin-creds -n monitoring \
  --from-literal=admin-user=admin --from-literal=admin-password="xxx" \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/monitoring/grafana-admin-creds.yaml
```

## Access

Grafana is a Tailscale LoadBalancer (`tailscale.com/hostname: grafana`) - reach it
at `https://grafana.<tailnet>` on the tailnet, like `kubeview`/`kube-ops-view`.
Prometheus/Alertmanager stay ClusterIP (port-forward when needed).

## Hooking an app in

Ship a `ServiceMonitor` next to the app selecting its metrics service; the open
selectors here mean no release label is required:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: my-app, namespace: my-app }
spec:
  selector: { matchLabels: { app.kubernetes.io/name: my-app } }
  endpoints: [ { port: http, path: /metrics } ]
```
App Grafana dashboards: ship as ConfigMaps labelled `grafana_dashboard` (any ns).
