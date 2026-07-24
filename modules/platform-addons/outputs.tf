output "external_dns_role_arn" {
  description = "ARN del IAM role de External-DNS."
  value       = aws_iam_role.external_dns.arn
}

output "cert_manager_role_arn" {
  description = "ARN del IAM role de Cert-Manager."
  value       = aws_iam_role.cert_manager.arn
}

output "compute_mode" {
  description = "Modo de cómputo activo y sus implicaciones."
  value       = var.enable_fargate ? "fargate" : "ec2"
}
