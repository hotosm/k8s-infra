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

## Alertmanager Slack

### Create the Slack app

At <https://api.slack.com/apps>, create an app from scratch, enable **Incoming
Webhooks**, add a webhook for `#hot-tech-alerts`, and copy its URL.

### Create the secret

```bash
kubectl create secret generic alertmanager-slack -n monitoring \
  --from-literal=webhook-url='https://hooks.slack.com/services/...' \
  --dry-run=client -o yaml | kubeseal -o yaml > apps/monitoring/alertmanager-slack.yaml
```

Create this before syncing; Alertmanager mounts it at startup.

### Test

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
curl -X POST localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"SlackIntegrationTest","severity":"critical"},"annotations":{"summary":"Alertmanager Slack test"}}]'
```

Confirm the test alert appears in `#hot-tech-alerts`.

## Access

Grafana is a Tailscale LoadBalancer (`tailscale.com/hostname: grafana`) - reach it
at `http://grafana.<tailnet>` on the tailnet, like `kubeview`/`kube-ops-view`.
Alertmanager and Prometheus are on the tailnet too, via `tailscale-services.yaml`
(the chart's Service templates have no `loadBalancerClass` field). Their
`externalUrl` in `helm/values.yaml` is what makes the links in Slack alerts
resolve - change both together if the tailnet name changes.

Note **http**, not https: a `loadBalancerClass: tailscale` Service publishes only
the ports it declares (here 80) and does not terminate TLS. HTTPS would need a
Tailscale `Ingress` instead, which provisions a tailnet cert.

Grafana uses `deploymentStrategy: Recreate` on purpose - see the comment in
`helm/values.yaml`. A RollingUpdate against its ReadWriteOnce PVC deadlocks on
volume attach and leaves the Service with no endpoints.

## Triaging a Slack alert

A new rule fires against pre-existing state, so the first burst after adding
alerts is usually a backlog, not a new incident.

```bash
# Deployments behind DeploymentNoReplicasAvailable
kubectl get deploy -A -o json | jq -r '.items[]
  | select(.spec.replicas > 0 and (.status.availableReplicas // 0) == 0)
  | "\(.metadata.namespace)/\(.metadata.name)"'

# Why a CNPG cluster cannot archive WAL
kubectl -n postgres logs <cluster>-1 -c postgres | grep -i archive | tail -20
kubectl -n postgres exec <cluster>-1 -c postgres -- psql -tAc 'select * from pg_stat_archiver'
```

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
**ScaleODM / ODM jobs** dashboard (per-job memory and CPU vs request, peak memory,
workspace fill, kills, node shape, swap; Argo controller metrics in a collapsed row).
It's a ConfigMap labelled `grafana_dashboard`, so the sidecar imports it automatically
- no Grafana-side config. It renders in UTC so graphs line up with container logs.

- **CloudNativePG** - every Postgres cluster in `databases/`: connections,
  replication lag, WAL, backups. Vendored to `apps/monitoring/cnpg-dashboard.yaml`
  from the upstream `cloudnative-pg/grafana-dashboards` repo; clusters appear once
  the `PodMonitor` at the bottom of their manifest in `databases/` is synced.

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

### Reading a peak off a timeseries

Grafana asks Prometheus for one sample per step, so on a 24h range at a 2-min step a
2-minute spike is a coin flip. Every gauge panel on the ScaleODM dashboard therefore
wraps its query:

```promql
max_over_time( ( <the query> )[$__interval:] )
```

Keep that wrapper on anything you add. Without it the memory panels understate the
peak, which is the number ScaleODM's sizing table is built from.

How to read an individual panel (anon vs page cache, disk saturation, what a pinned
limit means) is in its own description: hover the panel title in Grafana.

### When the controller panels are empty

The four panels in the collapsed **Argo controller** row are the only ones fed by the
controller itself; everything else comes from cAdvisor, kube-state-metrics or
node-exporter. All four empty at once means the scrape target is missing, not that the
queries are wrong - work down this list:

```bash
# 1. Is the ServiceMonitor there at all? The chart only renders it if the
#    monitoring.coreos.com CRD was visible when Argo CD templated the chart.
kubectl -n argo get servicemonitor scaleodm-argo-workflows-workflow-controller

# 2. Is the metrics Service there, with endpoints?
kubectl -n argo get svc,endpoints -l app.kubernetes.io/component=workflow-controller

# 3. Does the controller actually serve metrics?
kubectl -n argo port-forward deploy/scaleodm-argo-workflows-workflow-controller 9090:9090
curl -s localhost:9090/metrics | grep '^argo_workflows_' | cut -d'{' -f1 | sort -u

# 4. Has Prometheus picked the target up?
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[]
  | select(.labels.job|test("workflow-controller")) | {health, lastError, scrapeUrl}'
```

Step 3 is the one that settles it: it prints the metric names the deployed Argo actually
emits. The panels are written against the Argo 3.6+ names (`argo_workflows_gauge`,
`argo_workflows_total_count`, `argo_workflows_queue_depth_gauge`); the chart pins Argo
3.7.4 so these should match, but confirm against that output before editing a query.

`workflow_duration_seconds` is different - it is a per-workflow custom metric and only
appears once a workflow *completes*. An empty duration panel with the other three
populated is normal on a quiet day, not a fault.

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
