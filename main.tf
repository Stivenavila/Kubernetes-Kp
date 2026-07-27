## =============================================================
## Root Module — Orquestación de la plataforma EKS
## =============================================================

## -----------------------------------------------------
## Variable Cross-Validation
## -----------------------------------------------------

resource "terraform_data" "validate_network_inputs" {
  lifecycle {
    precondition {
      condition     = var.create_vpc || (var.existing_vpc_id != "" && can(regex("^vpc-[0-9a-f]+$", var.existing_vpc_id)))
      error_message = "Si create_vpc = false, se debe proporcionar un existing_vpc_id válido (vpc-xxxx)."
    }

    precondition {
      condition     = var.create_vpc || length(var.existing_private_subnet_ids) >= 2
      error_message = "Si create_vpc = false, se deben proporcionar al menos 2 subnets privadas en existing_private_subnet_ids."
    }

    precondition {
      condition     = var.create_vpc || length(var.existing_public_subnet_ids) >= 2
      error_message = "Si create_vpc = false, se deben proporcionar al menos 2 subnets públicas en existing_public_subnet_ids."
    }
  }
}

## -----------------------------------------------------
## VPC — creada solo si create_vpc = true
## -----------------------------------------------------

# Migra el state existente al pasar a index [0] (evita destroy de la VPC).
moved {
  from = module.vpc
  to   = module.vpc[0]
}

module "vpc" {
  source = "./modules/vpc"
  count  = var.create_vpc ? 1 : 0

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets     = local.public_subnets
  private_subnets    = local.private_subnets
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags  = local.public_subnet_tags
  private_subnet_tags = local.private_subnet_tags
}

## -----------------------------------------------------
## EKS Cluster + Node Groups
## -----------------------------------------------------

module "eks" {
  source = "./modules/eks"

  name_prefix        = local.name_prefix
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids
  public_subnet_ids  = local.public_subnet_ids

  cluster_version      = var.eks_cluster_version
  cluster_support_type = var.eks_support_type
  node_instance_types  = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_disk_size      = var.eks_node_disk_size

  # Compute mode derivado (fargate <-> ec2)
  enable_ec2_nodes          = local.enable_ec2_nodes
  enable_fargate            = local.is_fargate
  fargate_namespaces        = var.fargate_namespaces
  fargate_addon_namespaces  = var.fargate_addon_namespaces
  fargate_system_namespaces = var.fargate_system_namespaces
}

## -----------------------------------------------------
## Helm Add-ons (ArgoCD + Cilium with Gateway API + Hubble)
## -----------------------------------------------------

module "helm_addons" {
  source = "./modules/helm-addons"

  enable_argocd = var.enable_argocd
  enable_cilium = var.enable_cilium

  argocd_chart_version  = var.argocd_chart_version
  cilium_chart_version  = var.cilium_chart_version
  argocd_admin_password = var.argocd_admin_password_bcrypt
  ha_enabled            = var.environment == "prod" ? true : false

  # Espera a que nodos + CoreDNS + VPC CNI estén operativos antes de instalar Helm charts
  depends_on = [module.eks.node_group_ready]
}

## -----------------------------------------------------
## Karpenter — Node Autoscaling (solo compute_mode = ec2_karpenter)
## -----------------------------------------------------

module "karpenter" {
  source = "./modules/karpenter"
  count  = local.enable_karpenter ? 1 : 0

  name_prefix       = local.name_prefix
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_group_role_arn

  karpenter_version     = var.karpenter_version
  ha_enabled            = var.environment == "prod"
  use_spot              = var.karpenter_use_spot
  nodepool_cpu_limit    = var.karpenter_nodepool_cpu_limit
  nodepool_memory_limit = var.karpenter_nodepool_memory_limit

  depends_on = [module.eks]
}

## -----------------------------------------------------
## Platform Add-ons (VPA, HPA/Metrics Server, External-DNS,
##                   Cert-Manager)
## -----------------------------------------------------

module "platform_addons" {
  source = "./modules/platform-addons"

  name_prefix       = local.name_prefix
  aws_region        = var.aws_region
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  ha_enabled        = var.environment == "prod"

  enable_fargate = local.is_fargate

  # Feature flags
  enable_metrics_server    = var.enable_metrics_server
  enable_vpa               = var.enable_vpa
  enable_external_dns      = var.enable_external_dns
  enable_cert_manager      = var.enable_cert_manager
  enable_storage_class_gp3 = var.enable_storage_class_gp3

  # Chart versions
  vpa_chart_version            = var.vpa_chart_version
  external_dns_chart_version   = var.external_dns_chart_version
  cert_manager_chart_version   = var.cert_manager_chart_version
  metrics_server_chart_version = var.metrics_server_chart_version

  # External-DNS
  domain_filters = var.domain_filters

  # Cert-Manager
  letsencrypt_email = var.letsencrypt_email

  # Espera a que Cilium (CNI/network policy) esté operativo antes de desplegar addons de plataforma
  depends_on = [module.helm_addons.cilium_ready]
}

## -----------------------------------------------------
## Destroy Ordering Notes
## -----------------------------------------------------
## En modo Fargate, existe un ciclo inherente de Terraform al hacer
## `terraform destroy` completo:
##   provider[kubernetes] → module.eks outputs → aws_eks_cluster
##   → aws_eks_fargate_profile → (back to provider for namespace destroy)
##
## Para evitarlo, usar `make destroy` que ejecuta destroy en 3 pasos:
##   1. Destruye platform_addons + helm_addons (recursos kubernetes)
##   2. Destruye Karpenter
##   3. Destruye EKS + VPC + resto
##
## Si hay recursos fantasma en el state (ej: kubernetes_namespace.external_dns
## que ya no está en código), removerlos manualmente:
##   terraform state rm 'module.platform_addons.kubernetes_namespace.external_dns[0]'
## -----------------------------------------------------
