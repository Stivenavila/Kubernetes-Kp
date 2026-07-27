output "cluster_name" {
  description = "Nombre del cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint del API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "CA certificate del cluster (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  description = "ARN del cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_security_group_id" {
  description = "Security group ID del cluster."
  value       = aws_security_group.cluster.id
}

output "oidc_provider_arn" {
  description = "ARN del OIDC provider para IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL del OIDC provider (sin https://)."
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "node_group_role_arn" {
  description = "ARN del IAM role de los nodos."
  value       = aws_iam_role.node.arn
}

output "node_security_group_id" {
  description = "Security group ID del managed node group (EKS-managed)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Primary security group del cluster (auto-created by EKS)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_ready" {
  description = "Marker que indica que los nodos EC2 y CoreDNS están operativos. Usar como depends_on para Helm releases."
  value       = true

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_fargate_profile.system,
    aws_eks_addon.coredns,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
  ]
}
