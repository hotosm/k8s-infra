## Karpenter on hotosm-production-cluster

Karpenter provisions EC2 nodes on-demand for pods that don't fit on the
"core" managed nodegroup. The core nodegroup runs a fixed baseline (see
`var.core_nodegroup_size` in `terraform/`) for steady-state workloads;
Karpenter handles all capacity above that.

### Terraform interplay

Helm values:
- `serviceAccount.annotations.eks.amazonaws.com/role-arn` — IAM role from
  the OpenTofu output `karpenter_controller_role_arn`.
- `settings.interruptionQueue` matches `settings.clusterName` — Terraform
  creates an SQS queue with that name for spot-interruption handling.

Node Class (`ec2nodeclass.yaml`):
- `spec.role: KarpenterNodeRole-hotosm-production-cluster` must match the
  IAM instance profile from Terraform output
  `karpenter_node_instance_profile_name`.
- Subnets and security groups are discovered via the
  `karpenter.sh/discovery: hotosm-production-cluster` tag.

### Changing instance type / capacity / resources

Update the `-nodepool.yaml` manifest in this directory.

### Deployment

Run `tofu plan` / `tofu apply` first so the IAM role and SQS queue exist,
then let Argo sync this app.
