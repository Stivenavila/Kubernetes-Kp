variable "name_prefix" {
  description = "Prefijo para nombrar recursos."
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs de las subnets públicas."
  type        = list(string)
}

variable "cluster_version" {
  description = "Versión de Kubernetes."
  type        = string
}

variable "node_instance_types" {
  description = "Instance types para node group."
  type        = list(string)
}

variable "node_desired_size" {
  description = "Número deseado de nodos."
  type        = number
}

variable "node_min_size" {
  description = "Mínimo de nodos."
  type        = number
}

variable "node_max_size" {
  description = "Máximo de nodos."
  type        = number
}

variable "node_disk_size" {
  description = "Tamaño del disco en GB."
  type        = number
}

variable "enable_ec2_nodes" {
  description = "Crear managed node group EC2. false = Fargate puro."
  type        = bool
  default     = false
}

variable "enable_fargate" {
  description = "Habilitar Fargate profiles (system + workload)."
  type        = bool
  default     = true
}

variable "fargate_namespaces" {
  description = "Namespaces de aplicación para el Fargate profile de workloads."
  type        = list(string)
  default     = []
}

variable "fargate_addon_namespaces" {
  description = "Namespaces de addons de plataforma para Fargate (argocd, external-dns, cert-manager, etc.)."
  type        = list(string)
  default     = []
}

variable "fargate_system_namespaces" {
  description = "Namespaces de sistema para el Fargate profile de sistema (CoreDNS, addons)."
  type        = list(string)
  default     = ["kube-system"]
}

variable "cluster_support_type" {
  description = <<-EOT
    Tipo de soporte del cluster EKS:
      - "STANDARD":  Solo Standard Support. El cluster NO pasa automáticamente a Extended Support.
      - "EXTENDED":  (default AWS) Entra en Extended Support automáticamente al finalizar Standard.
    Más info: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  EOT
  type        = string
  default     = "EXTENDED"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.cluster_support_type)
    error_message = "cluster_support_type debe ser STANDARD o EXTENDED."
  }
}
