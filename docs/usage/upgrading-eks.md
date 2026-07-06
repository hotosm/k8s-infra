# Upgrading EKS

Runbook for a single-minor control-plane upgrade (e.g. `1.33` → `1.34`).
EKS only supports one minor version per upgrade — **never skip versions**.

Set the target version once, use it throughout:

```bash
export TARGET=1.34
export REGION=us-east-1
export CLUSTER=hotosm-production-cluster
```

## 1. Pre-checks

Look for blockers in EKS Insights:

```bash
aws eks list-insights --region $REGION --cluster-name $CLUSTER \
  --query 'insights[?insightStatus.status!=`PASSING`]'
```

Investigate anything not PASSING. Insights refreshes on AWS's own schedule (~daily), so it can lag reality by up to a day — cross-check against actual cluster state before treating a warning as blocking.

Check apps for removed APIs:

```bash
helm template <release> <chart> --kube-version $TARGET.0 2>&1 | grep -iE 'removed|deprecated'
```

Common breakers: `extensions/v1beta1`, `networking.k8s.io/v1beta1`, `policy/v1beta1`, `batch/v1beta1`, `autoscaling/v2beta*`.

## 2. Look up target versions

```bash
# Managed EKS add-ons
for addon in aws-ebs-csi-driver vpc-cni coredns kube-proxy; do
  echo "=== $addon ==="
  aws eks describe-addon-versions --region $REGION \
    --addon-name $addon --kubernetes-version $TARGET \
    --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' \
    --output text
done

# AL2023 x86_64 EKS AMI release (Karpenter CPU nodes)
aws ssm get-parameter --region $REGION \
  --name /aws/service/eks/optimized-ami/$TARGET/amazon-linux-2023/x86_64/standard/recommended/release_version \
  --query 'Parameter.Value' --output text
# → e.g. 1.34.9-20260625 — use the date part (20260625) in the Karpenter alias

# AL2023 x86_64 NVIDIA GPU AMI (Karpenter GPU nodes)
aws ssm get-parameter --region $REGION \
  --name /aws/service/eks/optimized-ami/$TARGET/amazon-linux-2023/x86_64/nvidia/recommended/image_id \
  --query 'Parameter.Value' --output text
```

Note: `describe-addon-versions` returns the "default" pinned version for the target Kubernetes minor. If the currently-installed version of vpc-cni or coredns is already ≥ the default and still marked compatible, keep it — no need to roll add-ons backwards. Only `kube-proxy` must be bumped to match the new control plane.

## 3. Update Terraform variables

Edit `terraform/variables.tf`:

```hcl
kubernetes_version  = "1.34"
ebs_driver_version  = "..."   # from step 2
vpc_cni_version     = "..."
coredns_version     = "..."
kube_proxy_version  = "..."
```

All must be bumped together in a single apply — EKS rejects add-on versions ahead of the control plane.

## 4. Update Karpenter AMIs

`apps/karpenter/ec2nodeclass.yaml` — CPU nodes:

```yaml
amiSelectorTerms:
  - alias: al2023@vYYYYMMDD   # date from step 2 release_version
```

`apps/karpenter/gpu-ec2nodeclass.yaml` — GPU nodes:

```yaml
amiSelectorTerms:
  - id: ami-xxxxxxxxx   # AMI ID from step 2 image_id
```

## 5. Apply Terraform

```bash
tofu -chdir=terraform -var-file vars/production.tfvars plan
tofu -chdir=terraform -var-file vars/production.tfvars apply
```

Control plane goes to $TARGET first (~10-15 min), then add-ons roll.

## 6. Upgrade the managed core nodegroup

**Important**: always pass `--kubernetes-version`. If you omit it, EKS defaults to the current cluster version and rolls nodes for no version change — wasted node churn.

```bash
aws eks update-nodegroup-version --region $REGION \
  --cluster-name $CLUSTER --nodegroup-name core \
  --kubernetes-version $TARGET
```

Watch progress:

```bash
aws eks describe-update --region $REGION \
  --name $CLUSTER --nodegroup-name core \
  --update-id <update-id-from-previous-output> \
  --query 'update.status'
```

Nodes drain and re-launch one at a time (respects PDBs), ~10-15 min for 5 nodes.

## 7. Roll Karpenter nodes

Once Argo syncs the new AMI selectors from step 4, existing Karpenter nodes are marked "drifted" and replaced automatically. Watch:

```bash
kubectl get nodes -w
kubectl get nodeclaim
```

If replacement is too slow, `kubectl cordon` + `kubectl drain` old nodes manually.

## 8. Verify

```bash
kubectl get nodes -o wide                                            # all on target version
kubectl get pods -A --field-selector=status.phase!=Running           # nothing stuck
kubectl get clusters.postgresql.cnpg.io -A                           # CNPG healthy
aws eks list-addons --region $REGION --cluster-name $CLUSTER
aws eks list-insights --region $REGION --cluster-name $CLUSTER \
  --query 'insights[?insightStatus.status!=`PASSING`]'
```

All Argo apps should show `Synced/Healthy`. Insights warnings may take up to a day to clear after the underlying condition is fixed.

## Notes

- All four EKS add-ons (`aws-ebs-csi-driver`, `vpc-cni`, `coredns`, `kube-proxy`) are Terraform-managed. Version bumps are variable changes only.
- New `aws_iam_role` or `aws_eks_addon` resources must carry `tags = { project = "k8s-control" }` — the CI role's IAM policy requires that tag on create actions. Copy the pattern from `terraform/addons.tf`.
- Skew tolerance: `kube-proxy` must match the control plane's minor (or be at most 1 behind); `coredns` and `vpc-cni` tolerate wider skew.
- Nodegroup version updates can't be cancelled once started. Double-check the command before hitting enter.
