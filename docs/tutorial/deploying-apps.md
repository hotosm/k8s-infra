# Deploying Apps In Kubernetes

From skillshare session 22/10/2025

## Namespaces

- Namespaces are logical partitions within a Kubernetes cluster.

- They allow you to group related resources and apply policies
  (role based authentication RBAC, resource quotas, network policies).

```bash
kubectl create namespace oam
```

- While it's possible to run a namespace per deployment
  environment - dev/stage/prod - it's a bit cleaner to
  have a separate cluster per environment.

- Namespaces can be used to easily organise logical
  application units, e.g. a `oam`, or `imagery` namespace.

## Anatomy of manifests

- Every Kubernetes manifest follows the same high-level structure:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
```

| Field          | Purpose                                                      |
| -------------- | ------------------------------------------------------------ |
| **apiVersion** | Defines which API group/version the resource uses.           |
| **kind**       | The type of resource (`Pod`, `Service`, `Deployment`, etc.). |
| **metadata**   | Identifiers: name, labels, annotations, namespace.           |
| **spec**       | The desired configuration (replicas, template, ports, etc.). |

## Networking: Services & Ingress

### Services

- A Service defines how to reach a set of Pods inside the cluster.

- Each Service has a stable virtual IP (ClusterIP) and DNS name,
  and routes traffic to all matching Pods via labels.

- Service types:
  - **ClusterIP**: internal only (default)
  - **NodePort**: expose a port on each node
  - **LoadBalancer**: integrate with cloud load balancers
  - **ExternalName**: DNS alias for external resources

Example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: oam
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

- Typically ClusterIP will be used for most apps, with
  an Ingress defined for the actual external access.

### Ingress

- An Ingress defines external access to Services, typically via HTTP/HTTPS.

- It acts as a router or reverse proxy, mapping domain names and paths to Services.

- Requires an **Ingress Controller** (e.g., NGINX, AWS ALB, Traefik).

Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: oam
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: nginx.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-service
                port:
                  number: 80
```

### Practical: make Nginx accessible

- From previous example, add the Service and Ingress definitions
  above to the same `nginx.yaml`, with each divided by `---` between.

```bash
# Apply over the top
kubectl apply -f nginx.yaml -n oam

# Verify
kubectl get ingress -n oam
kubectl get svc -n oam
```

- Access on `http://nginx.local`.

- Alternatively, we can do a port forward to access the internal
  service:

```bash
kubectl port-forward svc/nginx-service 8080:80
```

## Probes

- Probes let Kubernetes know whether your container is healthy
  and ready for traffic.

- **Liveness Probe**: checks if the container is still running
  properly. If it fails repeatedly, Kubernetes restarts the
  container.

- **Readiness Probe**: checks if the app is ready to serve traffic.
  If it fails, the pod is temporarily removed from Service endpoints.

### Practical: add probes to Nginx

- Add the following to the deployment spec in
  `nginx.yaml`:

```yaml
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
```

```bash
# Apply over the top
kubectl apply -f nginx.yaml -n oam

# View pod health
kubectl get pod -n oam
kubectl describe pod <pod-name> -n oam
```


## Resource constraints

- Resource requests and limits prevent a single container
  from consuming too many cluster resources.

| Type         | Purpose                                            |
| ------------ | -------------------------------------------------- |
| **requests** | The *minimum* guaranteed CPU/memory the Pod needs. |
| **limits**   | The *maximum* it can consume.                      |

### Practical: add resouce constraints to Nginx

- Add the following to the deployment spec in
  `nginx.yaml`:

```yaml
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 128Mi
```

```bash
# Apply over the top
kubectl apply -f nginx.yaml -n oam

# View pod health
kubectl get pod -n oam
kubectl describe pod <pod-name> -n oam
kubectl top pods -n oam
```

!!! note

        1 CPU = 1 vCPU core, 1000m = 1 core.
        Kubernetes schedules pods based on **requests**.
        **Limits** enforce hard caps.

## Rolling updates and rollbacks

- Deployments automatically perform rolling updates,
  replacing pods gradually to avoid downtime.

```bash
# Upgrade the container version using rolling update
kubectl set image deployment/nginx-deployment nginx=nginx:1.28-alpine -n oam

# Monitor update
kubectl rollout status deployment/nginx-deployment -n oam

# Rollback
kubectl rollout undo deployment/nginx-deployment -n oam
```
