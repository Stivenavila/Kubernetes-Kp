variable "name_prefix" {
  description = "Prefijo para nombrar recursos."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC."
  type        = string
}

variable "availability_zones" {
  description = "Lista de AZs."
  type        = list(string)
}

variable "public_subnets" {
  description = "Lista de CIDRs para subnets públicas."
  type        = list(string)
}

variable "private_subnets" {
  description = "Lista de CIDRs para subnets privadas."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Usar un solo NAT Gateway (ahorro de costos)."
  type        = bool
  default     = true
}

variable "public_subnet_tags" {
  description = "Tags adicionales para subnets públicas (ej. EKS discovery)."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Tags adicionales para subnets privadas (ej. EKS discovery)."
  type        = map(string)
  default     = {}
}
