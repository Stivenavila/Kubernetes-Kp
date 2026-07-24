output "api_gateway_invoke_url" {
  description = "URL base para invocar el API Gateway."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "api_gateway_id" {
  description = "ID del REST API."
  value       = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_arn" {
  description = "ARN del stage."
  value       = aws_api_gateway_stage.this.arn
}

output "nlb_dns_name" {
  description = "DNS del NLB interno."
  value       = aws_lb.internal.dns_name
}

output "nlb_arn" {
  description = "ARN del NLB interno."
  value       = aws_lb.internal.arn
}

output "target_group_arn" {
  description = "ARN del target group para registrar pods/services."
  value       = aws_lb_target_group.k8s_ingress.arn
}

output "vpc_link_id" {
  description = "ID del VPC Link."
  value       = aws_api_gateway_vpc_link.this.id
}

output "waf_web_acl_arn" {
  description = "ARN del WAF WebACL."
  value       = aws_wafv2_web_acl.api.arn
}
