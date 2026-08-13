AWS_PROFILE ?= default
CLUSTER_NAME = $(shell tofu -chdir=terraform output -var-file=vars/local.tfvars cluster_name)
S3_BACKUP_ROLE = $(shell tofu -chdir=terraform output -var-file=vars/local.tfvars s3_backup_role)

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
