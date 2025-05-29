AWS_PROFILE ?= default
CLUSTER_NAME = $(shell tofu -chdir=terraform output cluster_name)
S3_BACKUP_ROLE = $(shell tofu -chdir=terraform output s3_backup_role)

PGO_CHART_VERSION = 5.7.4
EOAPI_CHART_VERSION = 0.7.1

.DEFAULT_GOAL := help

$(VERBOSE).SILENT:

.PHONY: help

help: Makefile
	@echo
	@echo "Usage: make [target]"
	@echo
	@echo "Targets:"
	@sed -n 's/^##//p' $< | column -t -s ':'
	@echo

## kubeconfig: Configure kubectl to connect to EKS cluster
kubeconfig:
	aws eks update-kubeconfig --name $(CLUSTER_NAME)

## init-eoapi: Add eoAPI repo and install dependencies
init-eoapi:
	command -v helm >/dev/null 2>&1 || { echo "Helm is required but not installed"; exit 1; }
	echo "Installing PostgresQL operator chart (eoAPI dependency)"
	helm upgrade --install --set disable_check_for_upgrades=true pgo oci://registry.developers.crunchydata.com/crunchydata/pgo --version $(PGO_CHART_VERSION)
	echo "Adding eoAPI repository."
	helm repo add eoapi https://devseed.com/eoapi-k8s/

## deploy-eoapi: Upgrade or install eoAPI release
deploy-eoapi:
	helm repo list | grep "eoapi" >/dev/null 2>&1 || { echo "Not initialized, run 'make init-eoapi' before retrying"; exit 1; }
	helm upgrade --install --namespace eoapi --create-namespace eoapi eoapi/eoapi --version $(EOAPI_CHART_VERSION) -f kubernetes/helm/eoapi.yaml --set previousVersion=$(EOAPI_CHART_VERSION) --set postgrescluster.metadata.annotations.eks.amazonaws.com/role-arn=$(S3_BACKUP_ROLE)