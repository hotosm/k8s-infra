# Cluster Applications

See [initial migration outline](../proposal.md) for main HOT OSM applications.

Relevant Docs:
- [kubectl]
- [Helm]

## Global

### ClusterIssuer

Issue TLS certificates for the cluster via [cert-manager]. See also [eoAPI TLS section](#transport-layer-security-tls).

Install:
```sh
# ** See helm/eoapi-values.yaml for initial setup **
$ kubectl apply -f kubernetes/manifests/cluster-issuer.yaml
```

## eoAPI

Open source Earth Observation (EO) backend supporting Open Aerial Map (OAM).

Site: https://eoapi.dev/
Chart: https://github.com/developmentseed/eoapi-k8s

Install:
```sh
$ helm upgrade --install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version $PGO_VERSION
$ helm repo add eoapi https://devseed.com/eoapi-k8s/
$ helm upgrade --install --namespace eoapi --create-namespace eoapi eoapi/eoapi \
    --version $EOAPI_CHART_VERSION \
    -f kubernetes/helm/eoapi-values.yaml \
    --set previousVersion=$EOAPI_CHART_VERSION \
    --set postgrescluster.metadata.annotations."eks\.amazonaws\.com/role-arn"=$S3_BACKUP_ROLE
```

#### helmfile

A basic [helmfile] has been added for GitHub Actions, but its recommended to use outside of CI workflows to maintain consistency.

```sh
$ helmfile apply
```

Provided the values match, a similar workflow can be achieved with the Makefile commands if the additional install isn't desired.

### Configuration

See [eoAPI chart docs]. The following sections provide a basic outline of overlays, customizations, and considerations specific to HOT's initial implementation.

#### Transport Layer Security (TLS)

See [cert-manager docs] and [eoAPI guidance on cert-manager setup]. 

- Requires a domain controlled by HOT
- Issuer manifests and chart settings have been made available to provision certificates using [ingress annotations] and Let's Encrypt/[ACME]
- Step-by-step instructions can be found in the [eoapi values file](./helm/eoapi-values.yaml)
- Required for [iframing]

#### Backups

Enabled with default settings, see the [PostgresOperator docs] for further customization. 

Uses an [OIDC auth setup] to access S3, which requires propagating TF-managed information to K8s.

> [!NOTE]
> Further development to bridge and/or reorganize TF and K8s-provisioned resources may remove the need to set a `role-arn` annotation on each release.

#### Monitoring / Observability / Autoscaling

The eoAPI support chart adds Prometheus and Grafana tooling to enable systems analysis, visualization, and custom metrics for autoscaling. 

- [eoAPI support chart setup]: in-depth walkthrough
- [eoAPI chart configuration]: set HPA behavior for services
- [eoAPI support chart dependencies]: explore further customization, provider documentation

_Currently set to install once TLS is enabled in eoAPI._

## Tips + Commands

### Setup

#### Local Context

```sh
$ aws eks update-kubeconfig --name <cluster_name>
```

### Debugging

CLI manual will be most helpful:
```sh
$ kubectl --help
```

#### Examples

Basic cluster overview:
```sh
$ kubectl get pod,svc,deploy -A
```

Shell into default container on pod:
```sh
$ kubectl -n <ns> exec -it <pod> -- bash
# $
```

Inspect ingress details:
```sh
$ kubectl -n <ns> describe ingress/<ingress>
```

Redirect pod log output to file:
```sh
$ kubectl -n <ns> logs <pod> --all-containers=true >> file.log
```

[kubectl]:
  https://kubernetes.io/docs/reference/kubectl/
[Helm]:
  https://helm.sh/docs/
[Let's Encrypt]:
  https://letsencrypt.org/
[cert-manager]:
  https://cert-manager.io/
[cert-manager docs]:
  https://cert-manager.io/docs/configuration/
[helmfile]:
  https://github.com/helmfile/helmfile
[eoAPI chart docs]:
  https://github.com/developmentseed/eoapi-k8s/tree/975a26639fa3b8be7d3338220d6ea9c4470d8d15/docs
[iframing]:
  https://developmentseed.slack.com/archives/C08B8L61QTT/p1747740182369159?thread_ts=1747314980.658339&cid=C08B8L61QTT
[eoAPI guidance on cert-manager setup]:
  https://github.com/developmentseed/eoapi-k8s/blob/main/docs/unified-ingress.md#setting-up-tls-with-cert-manager
[ingress annotations]:
  https://cert-manager.io/docs/usage/ingress/
[ACME]:
  https://cert-manager.io/docs/configuration/acme/
[PostgresOperator docs]:
  https://access.crunchydata.com/documentation/postgres-operator/latest/tutorials/backups-disaster-recovery/backups
[OIDC auth setup]:
  https://access.crunchydata.com/documentation/postgres-operator/latest/tutorials/backups-disaster-recovery/backups#using-an-aws-integrated-identity-provider-and-role
[eoAPI support chart setup]:
  https://github.com/developmentseed/eoapi-k8s/blob/975a26639fa3b8be7d3338220d6ea9c4470d8d15/docs/autoscaling.md
[eoAPI chart configuration]:
  https://github.com/developmentseed/eoapi-k8s/blob/975a26639fa3b8be7d3338220d6ea9c4470d8d15/docs/configuration.md
[eoAPI support chart dependencies]:
  https://github.com/developmentseed/eoapi-k8s/blob/975a26639fa3b8be7d3338220d6ea9c4470d8d15/helm-chart/eoapi-support/Chart.yaml