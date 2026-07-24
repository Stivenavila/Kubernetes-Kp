## -----------------------------------------------------
## General
## -----------------------------------------------------

variable "name_prefix" {
  description = "Prefijo para nombrar recursos."
  type        = string
}

variable "aws_region" {
  description = "Región de AWS."
  type        = string
}

variable "cluster_name" {
  description = "Nombre del cluster EKS."
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

variable "ha_enabled" {
  description = "Habilitar HA para componentes que lo soporten."
  type        = bool
  default     = false
}

variable "enable_fargate" {
  description = "Indica si el cluster corre en Fargate. Deshabilita Falco y ajusta estrategia de escalado."
  type        = bool
  default     = false
}

## -----------------------------------------------------
## Chart Versions
## -----------------------------------------------------

variable "metrics_server_chart_version" {
  description = "Versión del chart de Metrics Server (requerido para HPA)."
  type        = string
  default     = "3.12.1"
}

variable "vpa_chart_version" {
  description = "Versión del chart de VPA."
  type        = string
  default     = "4.5.0"
}

variable "external_dns_chart_version" {
  description = "Versión del chart de External-DNS."
  type        = string
  default     = "1.14.5"
}

variable "cert_manager_chart_version" {
  description = "Versión del chart de Cert-Manager."
  type        = string
  default     = "1.15.1"
}



## -----------------------------------------------------
## External-DNS
## -----------------------------------------------------

variable "domain_filters" {
  description = "Lista de dominios que External-DNS puede gestionar."
  type        = list(string)
  default     = []
}

## -----------------------------------------------------
## Cert-Manager
## -----------------------------------------------------

variable "letsencrypt_email" {
  description = "Email para Let's Encrypt. Vacío = no crear ClusterIssuers."
  type        = string
  default     = ""
}


