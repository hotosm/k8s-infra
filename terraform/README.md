# Cluster Infrastructure

See [original proposal](../proposal.md) for background.

Defines AWS infrastructure for an EKS cluster managed via OpenTofu. The initial setup is based on an [eoAPI-compatible build].

Resource Overview (AWS):
- Control Plane (EKS v1.32)
- Node Group (EC2 Amazon Linux + ASG)
- Dedicated VPC
- Shared cluster resources (ingress, autoscaler, certificate manager)
- Block storage (EBS)
- Bucket provisioning (S3)
- State locking remote backend (S3 + Dynamo)
    - ([S3-only locking expected next release](https://github.com/opentofu/opentofu/issues/599))

Relevant Docs:
- [AWS EKS]
- [OpenTofu]


## Note

Reconfigure the backend before running any `tofu` commands outside of GitHub Actions to avoid colocating local state with live state.

```tf
# ./versions.tf

terraform {
  # Change backend or use different buckets/tables
  backend "s3" { }
}
```

OpenTofu supports the use of [variables in backend configuration](https://opentofu.org/docs/language/settings/backends/configuration/#variables-and-locals). The provided `local.tfvars` file intentionally omits state resources to prompt the user if new values aren't defined in an s3 backend.


## Tips + Commands

### Setup

#### AWS Auth

OpenTofu needs to connect with AWS for most all operations.

Make sure the AWS CLI is [installed](https://docs.aws.amazon.com/cli/v1/userguide/cli-chap-install.html) with a profile configured to access the target deployment account/region. Setup details vary based on organization policies, principal types, authentication methods, etc.

Non-default AWS credentials are typically set per session:
```sh
$ export AWS_PROFILE=<profile>
$ tofu plan #...
$ tofu apply #...
$ #...
```
Or per command:
```sh
$ AWS_PROFILE=<profile> tofu plan #...
$ AWS_PROFILE=<profile> tofu apply #...
$ AWS_PROFILE=<profile> #...
```
See [credential precedence] for other sourcing options. 

#### Working Directory

OpenTofu operations reference the current working directory. 

Either switch to the (root) module _before_ running `tofu` commands:
```sh
$ cd terraform
$ tofu plan
```
Or reference the correct directory _in_ `tofu` commands:
```sh
$ tofu -chdir=terraform plan
```

### Basic Provision + Teardown

```sh
$ tofu init
# ...
# OpenTofu has been successfully initialized!
```
```sh
$ tofu validate
# Success! The configuration is valid.
```
```sh
$ tofu plan
# ...
# Plan: X to add, Y to change, Z to destroy.
```
```sh
$ tofu apply
# ...
# Apply complete! Resources: X added, Y changed, Z destroyed.
```
```sh
$ tofu destroy
# ...
# Destroy complete! Resources: X destroyed.
```

[AWS EKS]:
  https://docs.aws.amazon.com/eks/
[OpenTofu]:
  https://opentofu.org/docs/
[eoAPI-compatible build]:
  https://github.com/developmentseed/eoapi-k8s-terraform
[credential precedence]:
  https://docs.aws.amazon.com/cli/v1/userguide/cli-chap-configure.html