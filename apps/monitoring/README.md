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

## Viewing it in Grafana

Nothing to build for the basics - the stack ships the kubernetes-mixin dashboards.
Search (Dashboards -> Browse) for:

- **Kubernetes / Compute Resources / Namespace (Pods)** - set namespace to `odm`
  for per-pod CPU/memory of every ODM job. The best starting point.
- **Kubernetes / Compute Resources / Node (Pods)** - what a given ScaleODM node ran.
- **Node Exporter / Nodes** - node CPU, memory, disk and swap.

For ScaleODM specifically, `apps/scaleodm/grafana-dashboard.yaml` ships a
**ScaleODM / ODM jobs** dashboard (workflow phases, job duration percentiles,
per-job memory, OOM kills, swap). It's a ConfigMap labelled `grafana_dashboard`,
so the sidecar imports it automatically - no Grafana-side config.

- **CloudNativePG** - every Postgres cluster in `databases/`: connections,
  replication lag, WAL, backups. Vendored to `apps/monitoring/cnpg-dashboard.yaml`
  from the upstream `cloudnative-pg/grafana-dashboards` repo; clusters appear
  once they have `monitoring.enablePodMonitor: true`.

For anything ad-hoc, use **Explore** and paste the queries below.

## Argo Workflows / batch jobs

The Argo controller (ns `argo`, from the ScaleODM chart) ships its own ServiceMonitor
- see `apps/scaleodm/helm/values.yaml`. Builtins are `argo_workflows_gauge{status}`
(live counts), `argo_workflows_total_count{phase,namespace}` (lifecycle totals) and
queue/error metrics. On top of those we add a `workflow_duration_seconds` histogram,
labelled `workflow_namespace` - not `namespace`, which would collide with the scrape
target's own label.

Container metrics have a `pod` label but no workflow name, so `metricLabelsAllowlist`
in `helm/values.yaml` publishes the Argo pod label to join on:

```promql
max by (label_workflows_argoproj_io_workflow) (       # peak memory per ODM job
  container_memory_working_set_bytes{namespace="odm", container!=""}
  * on (namespace, pod) group_left(label_workflows_argoproj_io_workflow)
    kube_pod_labels{namespace="odm"}
)
```

Compare with `kube_pod_container_resource_requests` to judge ScaleODM's sizing, and
`kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` for kills.
Allowlisted node labels give instance type and spot/on-demand via `kube_node_labels`.

### Swap

ODM pods are sized below their peak on purpose, with NVMe swap covering the gap
(`swapRatio` in `apps/scaleodm/helm/values.yaml`). Per-container swap is unavailable:
the chart drops `container_memory_swap`, and un-dropping it means copying all 8
upstream drop rules to edit one - so the chart's own
`node_namespace_pod_container:container_memory_swap` rule is always empty here.
Use node-exporter instead; the pool is dedicated, so node swap is job swap when a
single ODM pod owns the node:

```promql
(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes)   # swap used, per node
  * on (namespace, pod) group_left(node) kube_pod_info{namespace="monitoring"}

rate(node_vmstat_pswpin[5m])        # swap read rate - sustained means thrashing
increase(node_vmstat_oom_kill[1h])  # kernel OOM kills
```

Full swap is expected; a sustained swap-in rate is the problem. Figures blur if two
ODM pods share a node - check `count by (node) (kube_pod_info{namespace="odm"})`.
