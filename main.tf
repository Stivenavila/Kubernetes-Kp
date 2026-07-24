## =============================================================
## Root Module — Orquestación de la plataforma EKS
## =============================================================

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

  cluster_version     = var.eks_cluster_version
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_disk_size      = var.eks_node_disk_size

  # Compute mode derivado (fargate <-> ec2)
  enable_ec2_nodes          = local.enable_ec2_nodes
  enable_fargate            = local.is_fargate
  fargate_namespaces        = var.fargate_namespaces
  fargate_system_namespaces = var.fargate_system_namespaces
}

## -----------------------------------------------------
## Helm Add-ons (ArgoCD + Cilium with Gateway API + Hubble)
## -----------------------------------------------------

module "helm_addons" {
  source = "./modules/helm-addons"

  argocd_chart_version  = var.argocd_chart_version
  cilium_chart_version  = var.cilium_chart_version
  argocd_admin_password = var.argocd_admin_password_bcrypt
  ha_enabled            = var.environment == "prod" ? true : false

  depends_on = [module.eks]
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

  # Chart versions
  vpa_chart_version            = var.vpa_chart_version
  external_dns_chart_version   = var.external_dns_chart_version
  cert_manager_chart_version   = var.cert_manager_chart_version
  metrics_server_chart_version = var.metrics_server_chart_version

  # External-DNS
  domain_filters = var.domain_filters

  # Cert-Manager
  letsencrypt_email = var.letsencrypt_email

  depends_on = [module.eks]
}
