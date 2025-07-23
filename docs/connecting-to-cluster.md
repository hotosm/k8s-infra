# Connecting To The Cluster

- You will need both `aws-cli` and `kubectl` installed.

## Optional: Run Inside A Container

- To avoid installing heavy dependencies, accessing the cluster can be 
  done via container.
- Pull this image:
  `ghcr.io/spwoodcock/awscli-kubectl`
- Then create an alias:
  `alias aws-shell='docker run --rm -it -v /home/sam:/root --workdir /root ghcr.io/spwoodcock/awscli-kubectl:latest'`
- Simply run `aws-shell` before continuing below.

## Configure AWS CLI

```bash
# Configure SSO
aws configure sso --use-device-code
	Session name: admin
	Start URL: https://hotosm.awsapps.com/start/#
	Start region: eu-west-1
	Then login, and set profile name = admin

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
