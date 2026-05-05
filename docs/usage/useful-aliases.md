# Useful Shell Aliases

## Cluster Tools

```bash
alias k='kubectl'
alias kcc='kubie ctx'
alias ns='kubie ns'
```

## Copy Secret To Another Namespace

`copy-secret secret-name new-namespace`

```bash
function copy-secret
    kubectl get secret $argv[1] -o json \
    | jq 'del(.metadata["namespace","creationTimestamp","resourceVersion","selfLink","uid"])' \
    | kubectl apply -n $argv[2] -f -
end
```

## Cleanup Unused Replicasets

When deploying a new version of tool, the old replicaset
will remain with 0/0, for easy revert.

These can be cleaned up easily:

Enter the namespace you wish to run on, then:
`clean-replicasets`

```bash
function clean-replicasets --description "Delete Kubernetes ReplicaSets with 0 replicas"
    kubectl get rs -o jsonpath='{range .items[?(@.spec.replicas==0)]}{.metadata.name}{"\n"}{end}' \
    | xargs -r kubectl delete rs
end
```

## Export Sealed Secret Vars

- To update sealed secrets, they must be re-created.
- First, we can export the current secrets, outputting a
  command to run.
- We can modify this output command, updating secrets as needed.
- Then run the command to generate `secret.yaml` and rerun
  `kubeseal` over it for the final file:

`unseal-secret secret-name namespace-name`

```bash
function unseal-secret
    if test (count $argv) -lt 2
        echo "Usage: unseal-secret <secret-name> <namespace>"
        return 1
    end

    set secret_name $argv[1]
    set ns $argv[2]
    set secret_json (kubectl get secret $secret_name -n $ns -o json 2>/dev/null)

    if test $status -ne 0
        echo "Error: could not fetch secret '$secret_name' in namespace '$ns'"
        return 1
    end

    echo -n "kubectl create secret generic $secret_name"
    for key in (echo $secret_json | jq -r '.data | keys[]')
        set val (echo $secret_json | jq -r ".data[\"$key\"]" | base64 -d)
        echo -n " \\"
        echo ""
        echo -n "  --from-literal=$key='$val'"
    end
    echo " \\"
    echo "  --dry-run=client \\"
    echo "  --namespace=$ns \\"
    echo "  -o yaml > secret.yaml"
end
```

## Accessing CNPG Databases

`forward-db dronetm`

- For some reason a simple `kubectl port-forward` never works for me,
  when accessing databases via tools like DBeaver.
- This alias will forward the service using a socat container,
  making the db accessible on `localhost:5432`.

For bash
```bash
forward-db() {
  local ns="postgres" proxy="db-proxy-$1"
  local svc=$(kubectl get svc -n "$ns" -o name | grep "$1" | grep -- '-rw$' | sed 's|service/||')
  [ -z "$svc" ] && echo "No -rw service found matching '$1'" && return 1
  trap "kubectl delete pod -n $ns $proxy --ignore-not-found --wait=false" EXIT INT TERM
  kubectl run -n "$ns" "$proxy" --image=alpine/socat --restart=Never -- \
    tcp-listen:5432,fork,reuseaddr "tcp-connect:${svc}:5432"
  kubectl wait -n "$ns" --for=condition=Ready "pod/$proxy" --timeout=30s
  echo "Forwarding localhost:5432 -> $svc"
  kubectl port-forward -n "$ns" "$proxy" 5432:5432
  trap - EXIT INT TERM
  kubectl delete pod -n "$ns" "$proxy" --ignore-not-found --wait=false
}
```

For fish:
```fish
function forward-db
    set -l ns postgres
    set -l proxy "db-proxy-$argv[1]"
    set -l svc (kubectl get svc -n $ns -o name | grep $argv[1] | grep -- '-rw$' | sed 's|service/||')
    test -z "$svc" && echo "No -rw service found matching '$argv[1]'" && return 1
    function __forward_db_cleanup --on-signal INT --on-signal TERM
        kubectl delete pod -n postgres $proxy --ignore-not-found --wait=false
        functions -e __forward_db_cleanup
    end
    kubectl run -n $ns $proxy --image=alpine/socat --restart=Never -- \
        tcp-listen:5432,fork,reuseaddr "tcp-connect:$svc:5432"
    kubectl wait -n $ns --for=condition=Ready pod/$proxy --timeout=30s
    echo "Forwarding localhost:5432 -> $svc"
    kubectl port-forward -n $ns $proxy 5432:5432
    kubectl delete pod -n $ns $proxy --ignore-not-found --wait=false
    functions -e __forward_db_cleanup
end
```
