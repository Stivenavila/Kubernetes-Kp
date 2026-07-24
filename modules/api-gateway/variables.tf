variable "name_prefix" {
  description = "Prefijo para nombrar recursos."
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas para el NLB."
  type        = list(string)
}

variable "stage_name" {
  description = "Nombre del stage del API Gateway."
  type        = string
  default     = "v1"
}
