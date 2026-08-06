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
at `http://grafana.<tailnet>` on the tailnet, like `kubeview`/`kube-ops-view`.
Note **http**, not https: a `loadBalancerClass: tailscale` Service publishes only
the ports it declares (here 80) and does not terminate TLS. HTTPS would need a
Tailscale `Ingress` instead, which provisions a tailnet cert.
Prometheus/Alertmanager stay ClusterIP (port-forward when needed).

Grafana uses `deploymentStrategy: Recreate` on purpose - see the comment in
`helm/values.yaml`. A RollingUpdate against its ReadWriteOnce PVC deadlocks on
volume attach and leaves the Service with no endpoints.

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

## Argo Workflows / batch jobs

The Argo workflow controller (ns `argo`, installed by the ScaleODM chart) ships
its own ServiceMonitor - see `apps/scaleodm/helm/values.yaml`. It exports both
controller health (`argo_workflows_count{status=...}`, queue depth, error counts)
and per-workflow `workflow_duration_seconds` / `workflow_result_total`, labelled
by `namespace` so ScaleODM and OAM uploader workflows are distinguishable.

For what a job actually *consumed*, join cAdvisor to `kube_pod_labels` using the
Argo pod label surfaced via `metricLabelsAllowlist` in `helm/values.yaml`:

```promql
# peak working set per ODM job
max by (label_workflows_argoproj_io_workflow) (
  container_memory_working_set_bytes{namespace="odm", container!=""}
  * on (namespace, pod) group_left(label_workflows_argoproj_io_workflow)
    kube_pod_labels{namespace="odm"}
)
```

Node labels (`karpenter.sh/nodepool`, `karpenter.sh/capacity-type`,
`node.kubernetes.io/instance-type`) are allowlisted too, so the same join against
`kube_node_labels` shows which instance types and spot/on-demand capacity jobs
landed on.
