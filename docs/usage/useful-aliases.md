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

No port-forward needed: connect over Tailscale instead.
See [Access over Tailscale](../tutorial/postgres.md#access-over-tailscale).
