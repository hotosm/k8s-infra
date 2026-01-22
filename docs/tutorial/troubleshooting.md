# Troubleshooting

## Resource stuck in 'terminating' state

If it's been stuck for a long time (hours - days), then modifiy the
finalizer to allow the resource to terminate:

namespace
```bash
kubectl get namespace "stuck-namespace" -o json \
  | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
  | kubectl replace --raw /api/v1/namespaces/stuck-namespace/finalize -f -
```

pod
```bash
kubectl get pod stuck-pod-name -n drone -o json \
| jq 'del(.metadata.finalizers)' \
| kubectl replace --raw "/api/v1/namespaces/drone/pods/stuck-pod-name/finalize" -f -
```
