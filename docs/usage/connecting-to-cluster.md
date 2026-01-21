# Connecting To The Cluster

- You will need both `aws-cli` and `kubectl` installed.

## Optional: Run Inside A Container

- To avoid installing heavy dependencies, accessing the cluster can be 
  done via container.
- Pull this image:
  `ghcr.io/spwoodcock/awscli-kubectl`
- Then create an alias:
  `alias aws-shell='docker run --rm -it --network=host -v $HOME:/root --workdir /root ghcr.io/spwoodcock/awscli-kubectl:latest'`
- Simply run `aws-shell` before continuing below.

## Configure AWS CLI

```bash
# Configure SSO
aws configure sso --use-device-code

# Enter details
# Session name: admin
# Start URL: https://hotosm.awsapps.com/start/#
# Start region: eu-west-1
# Then login, and set profile name = admin

# Login to SSO
aws sso login --profile admin --use-device-code

# Gen kubeconfig (automatically appends to existing kubeconfig)
aws eks update-kubeconfig --profile admin --name hotosm-production-cluster --region us-east-1
```

## Use Kubectl

```bash
# If you are still logged in, ignore this step, otherwise
aws sso login --profile admin --use-device-code

kubectl get pods
```

## Read-Only Cluster Role

For contractors to view status of deployments etc.

### Creating it as admin

- Got to IAM Identity Center in the correct region.
- Add users + create a group for the users.
- Create a Permission Set with `AmazonEKSMCPReadOnlyAccess`.
- Create an 'AWS Account' that links the role and Permission Set.
- This is used as the `arn` below:

```bash
# Get ARN
aws iam get-role \
	--profile admin \
	--role-name AWSReservedSSO_ReadOnlyClusterAccessPermission_b0f9a40b216948f7

# Create access entry
aws eks create-access-entry \
  --profile admin \
  --cluster-name hotosm-production-cluster \
  --principal-arn 'arn:aws:iam::670261699094:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_ReadOnlyClusterAccessPermission_b0f9a40b216948f7' \
  --type STANDARD \
  --region us-east-1

# Associate access policy
aws eks associate-access-policy \
  --profile admin \
  --cluster-name hotosm-production-cluster \
  --principal-arn 'arn:aws:iam::670261699094:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_ReadOnlyClusterAccessPermission_b0f9a40b216948f7' \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster \
  --region us-east-1

# Check - if eksctl is available on your system
eksctl get iamidentitymapping --cluster hotosm-production-cluster \
  --region us-east-1 \
  --profile readonly
```

### Using the role

This role should have access to view pods / deployment progress,
but not modify things.

`~/.aws/config`
```toml
[profile readonly]
sso_session = readonly
sso_account_id = 670261699094
sso_role_name = ReadOnlyClusterAccessPermission
[sso-session readonly]
sso_start_url = https://hotosm.awsapps.com/start/#
sso_region = eu-west-1
sso_registration_scopes = sso:account:access
```

Terminal:
```bash
# Login to SSO
aws sso login --profile readonly --use-device-code

# Update Kubeconfig with access
aws eks update-kubeconfig --profile readonly --name hotosm-production-cluster --region us-east-1

# View pods
kubectl get pods
```
