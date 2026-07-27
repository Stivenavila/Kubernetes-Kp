## -----------------------------------------------------
## General
## -----------------------------------------------------

variable "project_name" {
  description = "Nombre del proyecto. Se usa como prefijo en todos los recursos."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "project_name debe ser lowercase alfanumérico con guiones, 3-25 chars."
  }
}

variable "environment" {
  description = "Ambiente de despliegue (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "aws_region" {
  description = "Región de AWS para el despliegue."
  type        = string
  default     = "us-east-1"
}

## -----------------------------------------------------
## Networking
## -----------------------------------------------------

variable "create_vpc" {
  description = <<-EOT
    true  = Terraform crea la VPC (module.vpc).
    false = Reusa una VPC existente vía existing_vpc_id + existing_*_subnet_ids.
  EOT
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID de la VPC existente. Requerido si create_vpc = false."
  type        = string
  default     = ""

  validation {
    condition     = var.existing_vpc_id == "" || can(regex("^vpc-[0-9a-f]+$", var.existing_vpc_id))
    error_message = "existing_vpc_id debe ser vacío o un vpc-id válido (vpc-xxxx)."
  }
}

variable "existing_private_subnet_ids" {
  description = "IDs de subnets privadas existentes. Requerido si create_vpc = false."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.existing_private_subnet_ids) == 0 || length(var.existing_private_subnet_ids) >= 2
    error_message = "existing_private_subnet_ids debe ser vacío o contener al menos 2 subnets."
  }
}

variable "existing_public_subnet_ids" {
  description = "IDs de subnets públicas existentes. Requerido si create_vpc = false y usas LBs públicos."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.existing_public_subnet_ids) == 0 || length(var.existing_public_subnet_ids) >= 2
    error_message = "existing_public_subnet_ids debe ser vacío o contener al menos 2 subnets."
  }
}

variable "vpc_cidr" {
  description = "CIDR block principal de la VPC. Solo aplica si create_vpc = true."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR válido."
  }
}

variable "availability_zones" {
  description = "Lista de AZs. Debe contener exactamente 3."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "Se requieren exactamente 3 availability zones."
  }
}

variable "single_nat_gateway" {
  description = "true = 1 NAT GW (dev/staging). false = 1 NAT GW por AZ (prod HA)."
  type        = bool
  default     = true
}

## -----------------------------------------------------
## EKS
## -----------------------------------------------------

variable "eks_cluster_version" {
  description = "Versión de Kubernetes para el cluster EKS."
  type        = string
  default     = "1.36"
}

variable "eks_support_type" {
  description = <<-EOT
    Tipo de soporte del cluster EKS:
      - "STANDARD":  Solo Standard Support. Sin cargos extra por version obsoleta.
      - "EXTENDED":  (default AWS) Pasa automaticamente a Extended Support ($0.60/hr extra).
  EOT
  type        = string
  default     = "EXTENDED"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.eks_support_type)
    error_message = "eks_support_type debe ser STANDARD o EXTENDED."
  }
}

variable "eks_node_instance_types" {
  description = "Instance types para el managed node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "eks_node_desired_size" {
  description = "Número deseado de nodos en el node group."
  type        = number
  default     = 3

  validation {
    condition     = var.eks_node_desired_size >= 1 && var.eks_node_desired_size <= 20
    error_message = "eks_node_desired_size debe estar entre 1 y 20."
  }
}

variable "eks_node_min_size" {
  description = "Mínimo de nodos en el node group."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Máximo de nodos en el node group."
  type        = number
  default     = 6
}

variable "eks_node_disk_size" {
  description = "Tamaño del disco EBS en GB para los nodos."
  type        = number
  default     = 50
}

variable "compute_mode" {
  description = <<-EOT
    Modo de cómputo del cluster. Controla node group EC2, Karpenter y Fargate profiles.
      - "fargate":       Serverless total. Sin nodos EC2. kube-system + workloads en Fargate.
      - "ec2_managed":   Managed node group EC2 fijo. Sin Karpenter. Sin Fargate.
      - "ec2_karpenter": Managed node group EC2 base + Karpenter para autoscaling. Sin Fargate.
    Conmutar Fargate <-> EC2 = cambiar SOLO esta variable.
  EOT
  type        = string
  default     = "fargate"

  validation {
    condition     = contains(["fargate", "ec2_managed", "ec2_karpenter"], var.compute_mode)
    error_message = "compute_mode debe ser: fargate, ec2_managed o ec2_karpenter."
  }
}

variable "fargate_namespaces" {
  description = "Namespaces de aplicación que correrán en Fargate (compute_mode = fargate)."
  type        = list(string)
  default     = ["default", "fargate-workloads"]
}

variable "fargate_addon_namespaces" {
  description = <<-EOT
    Namespaces de addons de plataforma que correrán en Fargate.
    Incluir los namespaces donde se despliegan ArgoCD, External-DNS, Cert-Manager, etc.
    Solo aplica si compute_mode = fargate.
  EOT
  type        = list(string)
  default     = ["argocd", "external-dns", "cert-manager"]
}

variable "fargate_system_namespaces" {
  description = "Namespaces de sistema en Fargate (CoreDNS, addons). Requerido para Fargate puro."
  type        = list(string)
  default     = ["kube-system"]
}

## -----------------------------------------------------
## Helm / Add-ons — Feature Flags
## -----------------------------------------------------

variable "enable_argocd" {
  description = "Instalar ArgoCD via Helm."
  type        = bool
  default     = true
}

variable "enable_cilium" {
  description = "Instalar Cilium (CNI + Gateway API + Hubble) via Helm."
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Instalar Metrics Server via Helm (requerido para HPA)."
  type        = bool
  default     = true
}

variable "enable_vpa" {
  description = "Instalar Vertical Pod Autoscaler via Helm."
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Instalar External-DNS via Helm."
  type        = bool
  default     = true
}

variable "enable_cert_manager" {
  description = "Instalar Cert-Manager via Helm."
  type        = bool
  default     = true
}

variable "enable_storage_class_gp3" {
  description = "Crear StorageClass gp3 como default."
  type        = bool
  default     = true
}

## -----------------------------------------------------
## Helm / Add-ons — Chart Versions
## -----------------------------------------------------

variable "argocd_chart_version" {
  description = "Versión del chart de ArgoCD."
  type        = string
  default     = "7.3.4"
}

variable "cilium_chart_version" {
  description = "Versión del chart de Cilium."
  type        = string
  default     = "1.16.5"
}

variable "argocd_admin_password_bcrypt" {
  description = "Password bcrypt hash para ArgoCD admin. Generar con: htpasswd -nbBC 10 '' PASSWORD | tr -d ':n' | sed 's/2y/2a/'"
  type        = string
  sensitive   = true
  default     = ""
}

## -----------------------------------------------------
## Karpenter
## -----------------------------------------------------

variable "karpenter_version" {
  description = "Versión del chart de Karpenter."
  type        = string
  default     = "1.0.5"
}

variable "karpenter_use_spot" {
  description = "Permitir instancias Spot en el NodePool de Karpenter."
  type        = bool
  default     = true
}

variable "karpenter_nodepool_cpu_limit" {
  description = "Límite total de CPU para el NodePool de Karpenter."
  type        = string
  default     = "100"
}

variable "karpenter_nodepool_memory_limit" {
  description = "Límite total de memoria para el NodePool de Karpenter."
  type        = string
  default     = "400Gi"
}

## -----------------------------------------------------
## Platform Add-ons Chart Versions
## -----------------------------------------------------

variable "metrics_server_chart_version" {
  description = "Versión del chart de Metrics Server."
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

variable "falco_chart_version" {
  description = "Versión del chart de Falco."
  type        = string
  default     = "4.7.0"
}

variable "prometheus_stack_chart_version" {
  description = "Versión del chart de kube-prometheus-stack."
  type        = string
  default     = "61.7.0"
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
  description = "Email para Let's Encrypt ClusterIssuers. Vacío = no crear."
  type        = string
  default     = ""
}

## -----------------------------------------------------
## Falco
## -----------------------------------------------------

variable "falco_slack_webhook" {
  description = "Slack webhook URL para alertas de Falco."
  type        = string
  sensitive   = true
  default     = ""
}

variable "falco_webui_enabled" {
  description = "Habilitar Falcosidekick Web UI."
  type        = bool
  default     = false
}

## -----------------------------------------------------
## Prometheus / Grafana
## -----------------------------------------------------

variable "grafana_admin_password" {
  description = "Password del admin de Grafana."
  type        = string
  sensitive   = true
  default     = "prom-operator"
}

variable "prometheus_retention" {
  description = "Período de retención de métricas."
  type        = string
  default     = "15d"
}

variable "prometheus_storage_size" {
  description = "Tamaño del PVC para Prometheus."
  type        = string
  default     = "50Gi"
}

## -----------------------------------------------------
## Tags
## -----------------------------------------------------

variable "extra_tags" {
  description = "Tags adicionales para todos los recursos."
  type        = map(string)
  default     = {}
}
