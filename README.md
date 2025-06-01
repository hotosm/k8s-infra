# HOT’s Infrastructure Modernization: Kubernetes

> [!Note]
> Currently under initial development. 

Kubernetes @ Humanitarian OpenStreetMap Team (HOT).

See the [inital proposal](docs/proposal.md) for more background.

## Getting Started

#### Required Tools

[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
[OpenTofu](https://opentofu.org/docs/intro/install/)
[kubectl](https://kubernetes.io/docs/tasks/tools/)
[Helm](https://helm.sh/docs/intro/install/)


Areas for Further (Initial) Development:

1. Variable Management
    1. Duplication exists between TF inputs, CI workflows, and local scripts.
    1. A tool like https://github.com/helmfile/helmfile may help with sourcing variables by environment.
        1. A basic version has been added to deploy revision deltas, further templating would be required.
    1. As more HOT applications + services are moved to cluster, this will only grow.
1. Deployment
    1. Provisioning is currently done in the same workflow (TF, K8s, Helm), mostly as byproduct of initial development phase. Can be further refined.
    1. GitOps tools like ArgoCD are [under consideration](https://github.com/hotosm/k8s-infra/issues/14)
    1. Flux [Tofu controller](https://github.com/flux-iac/tofu-controller) may be an analog for base infrastructure (further investigation required).
1. Bridging TF and Kubernetes
    1. TF-managed information often needs to be referenced on the cluster
        1. ex: PostgresCluster CRD requires the role ARN authorized for backups. Role and bucket are created in TF.
    1. Global cluster resources are provisioned through TF, but argument can be made for their management by K8s. 
    1. Ideal solution enables cluster resources to reference, mount, inject, etc. TF-managed information with minimal developer intervention.
