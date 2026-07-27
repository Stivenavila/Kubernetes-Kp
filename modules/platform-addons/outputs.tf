output "external_dns_role_arn" {
  description = "ARN del IAM role de External-DNS."
  value       = var.enable_external_dns ? aws_iam_role.external_dns[0].arn : ""
}

output "cert_manager_role_arn" {
  description = "ARN del IAM role de Cert-Manager."
  value       = var.enable_cert_manager ? aws_iam_role.cert_manager[0].arn : ""
}

output "compute_mode" {
  description = "Modo de cómputo activo y sus implicaciones."
  value       = var.enable_fargate ? "fargate" : "ec2"
}
