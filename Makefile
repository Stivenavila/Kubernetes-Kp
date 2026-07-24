# =============================================================
# EKS Platform — Makefile
# Encapsula el ciclo Terraform y el switch de compute_mode.
# =============================================================

SHELL := /bin/bash
REGION ?= us-east-1
PLAN   := tfplan

# Modo por defecto = el de terraform.tfvars. Override: make plan MODE=ec2_karpenter
# Si MODE está vacío, NO se pasa -var y manda tfvars.
MODE ?=
ifeq ($(strip $(MODE)),)
  VAR_MODE :=
else
  VAR_MODE := -var 'compute_mode=$(MODE)'
endif

.DEFAULT_GOAL := help

.PHONY: help
help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort | awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------- Validación (sin credenciales) ----------

.PHONY: fmt
fmt: ## Formatea todo el HCL
	terraform fmt -recursive

.PHONY: validate
validate: ## init offline + validate
	terraform init -backend=false -input=false
	terraform validate

# ---------- Ciclo real (requiere profile AWS + backend S3) ----------

.PHONY: init
init: ## Inicializa con backend S3
	terraform init -input=false

.PHONY: plan
plan: ## Dry-run. Uso: make plan [MODE=fargate|ec2_managed|ec2_karpenter]
	terraform plan $(VAR_MODE) -out=$(PLAN)

.PHONY: apply
apply: ## Aplica el plan guardado ($(PLAN))
	terraform apply $(PLAN)

.PHONY: destroy
destroy: ## Destruye toda la plataforma (CUIDADO)
	terraform destroy $(VAR_MODE)

# ---------- Switch de modo (plan → revisar → apply) ----------

.PHONY: switch-fargate
switch-fargate: ## Plan hacia Fargate puro
	$(MAKE) plan MODE=fargate

.PHONY: switch-ec2
switch-ec2: ## Plan hacia EC2 managed node group
	$(MAKE) plan MODE=ec2_managed

.PHONY: switch-karpenter
switch-karpenter: ## Plan hacia EC2 + Karpenter
	$(MAKE) plan MODE=ec2_karpenter

# ---------- Post-apply ----------

.PHONY: kubeconfig
kubeconfig: ## Actualiza kubeconfig del cluster
	aws eks update-kubeconfig --region $(REGION) \
		--name $$(terraform output -raw eks_cluster_name)

.PHONY: status
status: ## Muestra modo activo, nodos y pods
	@echo "== compute_mode ==" && terraform output -raw compute_mode; echo
	@echo "== nodes (vacío en fargate) ==" && kubectl get nodes 2>/dev/null || true
	@echo "== pods ==" && kubectl get pods -A -o wide 2>/dev/null || true
