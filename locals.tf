locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # -----------------------------------------------------
  # Flags derivados de compute_mode (unica fuente de verdad)
  # -----------------------------------------------------
  is_fargate       = var.compute_mode == "fargate"
  enable_ec2_nodes = contains(["ec2_managed", "ec2_karpenter"], var.compute_mode)
  enable_karpenter = var.compute_mode == "ec2_karpenter"

  # -----------------------------------------------------
  # Fuente de red: VPC creada (module.vpc) vs. existente (vars).
  # one(splat) evita error de índice cuando el módulo tiene count = 0.
  # -----------------------------------------------------
  vpc_id             = var.create_vpc ? one(module.vpc[*].vpc_id) : var.existing_vpc_id
  private_subnet_ids = var.create_vpc ? one(module.vpc[*].private_subnet_ids) : var.existing_private_subnet_ids
  public_subnet_ids  = var.create_vpc ? one(module.vpc[*].public_subnet_ids) : var.existing_public_subnet_ids

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    },
    var.extra_tags
  )

  # Subnet CIDRs — /20 blocks (4094 IPs each)
  # Public:  10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  # Private: 10.0.48.0/20, 10.0.64.0/20, 10.0.80.0/20
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i + 3)]

  # EKS required tags for subnet auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                         = "1"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                = "1"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  }
}
