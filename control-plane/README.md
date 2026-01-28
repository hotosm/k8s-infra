# TalosOS Control Plane

> [!NOTE]
> We don't use this for now.
> See https://github.com/hotosm/k8s-infra/issues/1

As of 16-10-2025 we are still using an EKS control plane for
our primary cluster.

In future we may need to migrate, and TalosOS is a good option.
https://github.com/siderolabs/contrib/tree/main/examples/terraform/aws

The official AWS manual Talos config can be found
[here](https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/cloud-platforms/aws).

## Setup

- Clone the terraform config from the repo above into this dir.
- All variables here: https://github.com/siderolabs/contrib/tree/main/examples/terraform/aws

## Running

```bash
tofu init
tofu plan
tofu apply --dry-run=client
```
