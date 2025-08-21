# Routing To Cluster Applications

The networking chain is like this:

User --> AWS Route53 DNS Record --> AWS Elastic Load Balancer (DualStack)
--> EKS Cluster Endpoint --> k8s Ingress --> k8s Service --> k8s Application

## Provisioning DNS Records

## Automatic DNS (external-dns)

- We have the `external-dns` operator installed in the cluster, which
  can automatically provision Route53 domains on request.
- Authentication with Route53 is done via static credentials:
  - This means we simply use an IAM User with assigned access/secret
    key pair.
  - Typically IAM Roles for Service Accounts are recommended instead,
    for generation or automatic temporary credentials.
  - We use static credentials for (1) simplicity (2) less reliance
    on AWS specific config, allowing for easier migration away if
    needed.
  - To improve security, we strictly limit IAM access for the user.

There is a great guide for doing this in the
[official external-dns docs](https://kubernetes-sigs.github.io/external-dns/v0.14.2/tutorials/aws/#static-credentials),
but the main steps are below.

### Configuring external-dns

- Create policy.json

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/Z007708822IRWZYIAATO8",
        "arn:aws:route53:::hostedzone/Z01079471L60VTHK00IFQ"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
```

- Create a policy from `policy.json`:

```bash
aws --profile admin iam create-policy --policy-name "k8sExternalDnsRoute53" --policy-document file://policy.json

# example: arn:aws:iam::XXXXXXXXXXXX:policy/k8sExternalDnsRoute53
export POLICY_ARN=$(aws --profile admin iam list-policies \
 --query 'Policies[?PolicyName==`k8sExternalDnsRoute53`].Arn' --output text)
```

- Create users with the attached policy:

```bash
# create IAM user
aws --profile admin iam create-user --user-name "externaldns"

# attach policy arn created earlier to IAM user
aws --profile admin iam attach-user-policy --user-name "externaldns" --policy-arn $POLICY_ARN
```

- Create security creds:

```bash
SECRET_ACCESS_KEY=$(aws --profile admin iam create-access-key --user-name "externaldns")
ACCESS_KEY_ID=$(echo $SECRET_ACCESS_KEY | jq -r '.AccessKey.AccessKeyId')

cat <<-EOF > credentials
[default]
aws_access_key_id = $(echo $ACCESS_KEY_ID)
aws_secret_access_key = $(echo $SECRET_ACCESS_KEY | jq -r '.AccessKey.SecretAccessKey')
EOF
```

- Create a **sealed secret** for storing in this repo:

```bash
kubectl create secret generic external-dns-aws-creds \
  --from-file=credentials=./credentials \
  --namespace kube-system \
  --dry-run=client -o yaml > secret.yaml

kubeseal -f secret.yaml -w sealed-secret.yaml
# Move the file to apps/external-dns/sealed-secret.yaml
# The secret.yaml can be discarded
```

### Using external-dns

- It' works by adding annotations such as:
  `external-dns.alpha.kubernetes.io/hostname: api.imagery.hotosm.org`
- The annotation is picked up when an Ingress is made, and the
  DNS entry is automatically made in Route53.

### Updating external-dns

- To update in future (e.g. update version), modify the file:
  `apps/external-dns.yaml`
- To add a new hosted zone:
  1. Modify the IAM Policy to include the Zone ID.
  2. Modify the helm values to include the domain.

## Manual DNS

- This shouldn't need to be done, but just for information
  about how this works.
- Go to Route53 and create a new A record.
- Check 'Alias' and 'Alias to Application and Classic Load Balancer'.
- Set region to `us-east-1`.
- We are currently using 'classic' load balancer:
  `dualstack.a1294ee7c4d2e41de88a0a5451b065b4-1435866857.us-east-1.elb.amazonaws.com.`
