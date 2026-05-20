## Karpenter on hotosm-production-cluster

OpenTofu and the ArgoCD config must interplay a bit here.

Helm values:
- `serviceAccount.annotations.eks.amazonaws.com/role-arn`, IAM role from
     from OpenTofu `karpenter_controller_role_arn`.
- `settings.interruptionQueue`, matches `settings.clusterName`, as we
  create an SQS queue via OpenTofu with the same name.

Node Class (`ec2nodeclass.yaml`):
- Uses `spec.role: KarpenterNodeRole-hotosm-production-cluster`,
  which must match the IAM instance profile created by Terraform output
  `karpenter_node_instance_profile_name`.
- It discovers subnets and security groups via the
  `karpenter.sh/discovery: hotosm-production-cluster` tag.

To change the instance type / capacity / resources,
update the `-nodepool.yaml` manifest here.

### Deployment notes

- Run the `opentofu plan` first.
- Apply this config to deploy Karpenter.

### Migration away from Cluster Autoscaler

- Cluster autoscaler is less capable than Karpenter.
- Deploy both Karpenter & keep cluster autoscaler to begin with.
- Then start scaling the cluster autoscaler nodegroup down
  (this will shift load into Karpenter):

```bash
CLUSTER_NAME=hotosm-production-cluster
NODEGROUP=core

aws eks update-nodegroup-config --cluster-name "${CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP}" \
  --scaling-config "minSize=2,maxSize=2,desiredSize=2"
```

- When Karpenter is observed to be scaling well, turn off
  autoscaler:

```bash
kubectl scale deploy/cluster-autoscaler -n cluster-autoscaler --replicas=0
```

- Gradually reduce down the managed nodegroup size:

```bash
aws eks update-nodegroup-config --cluster-name "${CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP}" \
  --scaling-config "minSize=1,maxSize=1,desiredSize=1"
```

- Remove the terraform config for autoscaler:

helm-repos.tf
```
helm_release "autoscaler" in helm-repos.tf.
```

cluster.tf
```
data "aws_iam_policy_document" "cluster_autoscaler"
aws_iam_role "cluster_autoscaler"
aws_iam_policy "cluster_autoscaler"
aws_iam_role_policy_attachment "cluster_autoscaler"
```

- Re-run a tofu plan / apply.
