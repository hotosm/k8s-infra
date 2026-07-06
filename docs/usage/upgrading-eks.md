# Upgrading EKS

Runbook for a single-minor control-plane upgrade (e.g. `1.33` → `1.34`).
EKS only supports one minor version per upgrade - **never skip versions**.

## 1. Pre-checks

Look for blockers in EKS Insights:

```bash
aws eks list-insights \
  --cluster-name hotosm-production-cluster --region us-east-1 \
  --query 'insights[?insightStatus.status!=`PASSING`]'
```

Investigate anything not PASSING. Insights refreshes on AWS's own schedule (roughly daily), so it can lag reality by up to a day - cross-check against actual cluster state before treating a warning as blocking.

Check apps for removed APIs by rendering charts against the target version:

```bash
helm template <release> <chart> --kube-version 1.34.0 2>&1 | grep -iE 'removed|deprecated'
```

Common issues: `extensions/v1beta1`, `networking.k8s.io/v1beta1`, `policy/v1beta1`, `batch/v1beta1`, `autoscaling/v2beta*`.

## 2. Look up target versions

For the target Kubernetes version, find the compatible defaults:

```bash
export TARGET=1.34

# Managed EKS add-ons
for addon in aws-ebs-csi-driver vpc-cni coredns kube-proxy; do
  echo "=== $addon ==="
  aws eks describe-addon-versions --region us-east-1 \
    --addon-name $addon --kubernetes-version $TARGET \
    --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' \
    --output text
done

# AL2023 x86_64 standard EKS AMI release (Karpenter CPU nodes)
aws ssm get-parameter --region us-east-1 \
  --name /aws/service/eks/optimized-ami/$TARGET/amazon-linux-2023/x86_64/standard/recommended/release_version \
  --query 'Parameter.Value' --output text
# → e.g. 1.34.6-20260420 - use the date part in the Karpenter alias

# AL2023 x86_64 NVIDIA GPU AMI (Karpenter GPU nodes)
aws ssm get-parameter --region us-east-1 \
  --name /aws/service/eks/optimized-ami/$TARGET/amazon-linux-2023/x86_64/nvidia/recommended/image_id \
  --query 'Parameter.Value' --output text
# → e.g. ami-0abc123def4567890
```

## 3. Update Terraform

Bump the version variables in `terraform/variables.tf` (or the active tfvars file):

```hcl
kubernetes_version  = "1.34"
ebs_driver_version  = "..."   # from step 2
vpc_cni_version     = "..."
coredns_version     = "..."
kube_proxy_version  = "..."
```

Terraform sequences these correctly inside a single apply - the control plane upgrades first, then the add-ons. EKS rejects add-on versions ahead of the control plane, so all five variables must be bumped together.

## 4. Update Karpenter AMIs

Karpenter uses pinned AMIs so nodes don't silently drift to untested images. Both files live in `apps/karpenter/`.

**CPU nodes** - `ec2nodeclass.yaml`:

```yaml
amiSelectorTerms:
  - alias: al2023@vYYYYMMDD   # date from step 2 release_version
```

**GPU nodes** - `gpu-ec2nodeclass.yaml`:

```yaml
amiSelectorTerms:
  - id: ami-xxxxxxxxx   # AMI ID from step 2 image_id
```

## 5. Apply Terraform

```bash
tofu -chdir=terraform plan     # confirm only expected diffs
tofu -chdir=terraform apply
```

Then update the managed `core` nodegroup - Terraform doesn't drive its kubelet version automatically:

```bash
aws eks update-nodegroup-version --region us-east-1 \
  --cluster-name hotosm-production-cluster --nodegroup-name core
```

This drains and re-launches core nodes one at a time (respects PDBs).

## 6. Roll Karpenter nodes

Once Argo syncs the new AMI selectors, existing Karpenter nodes are marked "drifted" and get replaced gradually. Watch:

```bash
kubectl get nodes -w
kubectl get nodeclaim
```

Old nodes drain and terminate over ~5–15 min. If replacement is too slow, cordon+drain manually.

## 7. Verify

```bash
kubectl get nodes -o wide                                # all on target version
kubectl get pods -A --field-selector=status.phase!=Running
kubectl get clusters.postgresql.cnpg.io -A               # CNPG databases healthy
aws eks list-addons --cluster-name hotosm-production-cluster --region us-east-1
aws eks list-insights --cluster-name hotosm-production-cluster --region us-east-1 \
  --query 'insights[?insightStatus.status!=`PASSING`]'
```

All Argo apps should show `Synced/Healthy`. Any residual WARNING in Insights may take up to a day to clear after the underlying condition is fixed - cross-check `describe-addon` output against `describe-cluster` version to confirm the reality.

## Notes

- All four EKS add-ons (`aws-ebs-csi-driver`, `vpc-cni`, `coredns`, `kube-proxy`) are Terraform-managed. Version bumps are variable changes only.
- New `aws_iam_role` or `aws_eks_addon` resources created by CI must carry `tags = { project = "k8s-control" }` - the CI role's IAM policy requires that tag on create actions. Copy the pattern from `terraform/addons.tf`.
- Skew tolerance: `kube-proxy` must match the control plane's minor version (or be at most 1 behind); `coredns` and `vpc-cni` tolerate wider skew.
