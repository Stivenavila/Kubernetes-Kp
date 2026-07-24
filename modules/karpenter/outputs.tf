output "karpenter_role_arn" {
  description = "ARN del IAM role de Karpenter."
  value       = aws_iam_role.karpenter_controller.arn
}

output "interruption_queue_name" {
  description = "Nombre de la SQS queue para interrupciones."
  value       = aws_sqs_queue.karpenter_interruption.name
}
