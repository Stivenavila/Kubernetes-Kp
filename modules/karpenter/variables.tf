variable "name_prefix" {
  description = "Prefijo para nombrar recursos."
  type        = string
}

variable "cluster_name" {
  description = "Nombre del cluster EKS."
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint del cluster EKS."
  type        = string
}

variable "cluster_arn" {
  description = "ARN del cluster EKS."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN del OIDC provider."
  type        = string
}

variable "oidc_provider_url" {
  description = "URL del OIDC provider (sin https://)."
  type        = string
}

variable "node_role_arn" {
  description = "ARN del IAM role de los nodos EC2."
  type        = string
}

variable "karpenter_version" {
  description = "Versión del chart de Karpenter."
  type        = string
  default     = "1.0.5"
}

variable "ha_enabled" {
  description = "Habilitar HA (2 replicas) para Karpenter."
  type        = bool
  default     = false
}

variable "use_spot" {
  description = "Permitir instancias Spot en el NodePool."
  type        = bool
  default     = true
}

variable "nodepool_cpu_limit" {
  description = "Límite total de CPU para el NodePool."
  type        = string
  default     = "100"
}

variable "nodepool_memory_limit" {
  description = "Límite total de memoria para el NodePool."
  type        = string
  default     = "400Gi"
}
