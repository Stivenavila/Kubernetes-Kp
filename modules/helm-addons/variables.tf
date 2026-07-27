variable "argocd_chart_version" {
  description = "Versión del chart de ArgoCD."
  type        = string
}

variable "cilium_chart_version" {
  description = "Versión del chart de Cilium."
  type        = string
  default     = "1.16.5"
}

variable "argocd_admin_password" {
  description = "BCrypt hash del password de admin de ArgoCD."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ha_enabled" {
  description = "Habilitar HA para ArgoCD y Cilium operator (prod)."
  type        = bool
  default     = false
}

## -----------------------------------------------------
## Feature Flags
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
