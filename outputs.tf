## =============================================================
## Root Outputs
## =============================================================

# VPC (creada o existente, según create_vpc)
output "vpc_id" {
  description = "ID de la VPC en uso (creada o existente)."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas en uso."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas en uso."
  value       = local.public_subnet_ids
}

output "vpc_managed_by_terraform" {
  description = "true si Terraform gestiona la VPC; false si es preexistente."
  value       = var.create_vpc
}

# EKS
output "eks_cluster_name" {
  description = "Nombre del cluster EKS."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint del cluster EKS."
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "ARN del OIDC provider para IRSA."
  value       = module.eks.oidc_provider_arn
}

output "eks_update_kubeconfig_command" {
  description = "Comando para actualizar kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ArgoCD
output "argocd_namespace" {
  description = "Namespace de ArgoCD."
  value       = module.helm_addons.argocd_namespace
}

# Networking
output "network_policy_engine" {
  description = "Engine de NetworkPolicy activo."
  value       = module.helm_addons.network_policy_engine
}

output "gateway_api_controller" {
  description = "Controller de Gateway API activo."
  value       = module.helm_addons.gateway_api_controller
}

# Compute mode
output "compute_mode" {
  description = "Modo de cómputo activo del cluster."
  value       = var.compute_mode
}

# Karpenter (solo compute_mode = ec2_karpenter)
output "karpenter_role_arn" {
  description = "ARN del IAM role de Karpenter. Null si no es ec2_karpenter."
  value       = local.enable_karpenter ? module.karpenter[0].karpenter_role_arn : null
}

output "karpenter_interruption_queue" {
  description = "SQS queue para interrupciones de Spot. Null si no es ec2_karpenter."
  value       = local.enable_karpenter ? module.karpenter[0].interruption_queue_name : null
}

# Scaling mode info
output "scaling_strategy" {
  description = "Estrategia de escalado activa según el compute mode."
  value = local.is_fargate ? {
    mode       = "fargate"
    horizontal = "HPA (metrics-server) — escala por replicas"
    vertical   = "VPA — ajusta requests/limits por pod"
    node       = "N/A — AWS gestiona infra por pod"
    } : {
    mode       = var.compute_mode
    horizontal = local.enable_karpenter ? "Karpenter — escala nodos EC2 (Spot + On-Demand)" : "HPA (metrics-server) — escala replicas sobre node group fijo"
    vertical   = "VPA — ajusta requests/limits por pod"
    node       = local.enable_karpenter ? "Karpenter NodePool: c/m/r/t gen≥3" : "Managed node group fijo (desired/min/max)"
  }
}
