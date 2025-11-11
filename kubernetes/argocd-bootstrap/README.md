# ArgoCD Bootstrap

## First Steps

- In order to use a GitOps approach to deploy apps via ArgoCD,
  first we need to configure ArgoCD.

- Install ArgoCD via [official guide](https://argo-cd.readthedocs.io/en/stable/getting_started)

- Install ArgoCD CLI:

    ```bash
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
    ```

- Get the initial ArgoCD password:

    ```bash
    argocd admin initial-password -n argocd
    kubectl port-forward svc/argocd-server -n argocd 8081:443 &
    argocd login argocd login localhost:8081
    argocd account update-password
    ```

- Access the UI:

    ```bash
    kubectl port-forward svc/argocd-server -n argocd 8080:443
    # Visit https://localhost:8080
    ```

## Boostrap Root App

ArgoCD must be bootstrapped to scan our repo and deploy apps.

```bash
kubectl apply -f root-app.yaml
```

## Backup Sealed Secrets Key!

- After the sealed secrets operator is deployed, it's a good
  idea to backup the main key:

    ```bash
    kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >main.key
    ```

- This should be stored super securely!
