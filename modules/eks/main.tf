## -----------------------------------------------------
## EKS Cluster
## -----------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  upgrade_policy {
    support_type = var.cluster_support_type
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Name = "${var.name_prefix}-eks"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

## -----------------------------------------------------
## KMS Key for EKS Secrets Encryption
## -----------------------------------------------------

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption - ${var.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.name_prefix}-eks-kms"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name_prefix}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

## -----------------------------------------------------
## Cluster Security Group
## -----------------------------------------------------

resource "aws_security_group" "cluster" {
  name_prefix = "${var.name_prefix}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-eks-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all egress from cluster"
}

## -----------------------------------------------------
## Managed Node Group (EC2) — solo en modos ec2_*
## -----------------------------------------------------

# Preserva el recurso existente al pasar a index [0] (evita destroy/recreate).
moved {
  from = aws_eks_node_group.main
  to   = aws_eks_node_group.main[0]
}

resource "aws_eks_node_group" "main" {
  count = var.enable_ec2_nodes ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-main-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role       = "general"
    managed-by = "eks"
    node-type  = "ec2"
  }

  tags = {
    Name = "${var.name_prefix}-main-ng"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

## -----------------------------------------------------
## Fargate Profiles (Conditional)
## Se separan system y workload: EKS serializa la creación de
## profiles (no concurrente), y CoreDNS depende del profile de
## sistema. El profile de sistema habilita kube-system en Fargate.
## -----------------------------------------------------

# Profile de SISTEMA (kube-system → CoreDNS, addons).
resource "aws_eks_fargate_profile" "system" {
  count = var.enable_fargate ? 1 : 0

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${replace(var.name_prefix, "/^eks-/", "")}-system"
  pod_execution_role_arn = aws_iam_role.fargate[0].arn
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = var.fargate_system_namespaces
    content {
      namespace = selector.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-fargate-system"
  }
}

# Preserva el profile previo si existía (no-op si el default era EC2).
moved {
  from = aws_eks_fargate_profile.this
  to   = aws_eks_fargate_profile.workload
}

# Profile de WORKLOADS (namespaces de aplicación).
resource "aws_eks_fargate_profile" "workload" {
  count = var.enable_fargate ? 1 : 0

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${replace(var.name_prefix, "/^eks-/", "")}-workload"
  pod_execution_role_arn = aws_iam_role.fargate[0].arn
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = var.fargate_namespaces
    content {
      namespace = selector.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-fargate-workload"
  }

  # EKS no permite crear profiles en paralelo.
  depends_on = [aws_eks_fargate_profile.system]
}

# Profile de ADDONS (argocd, external-dns, cert-manager, etc.)
# Sin este profile, los pods de addons quedan en Pending en modo Fargate puro.
resource "aws_eks_fargate_profile" "addons" {
  count = var.enable_fargate && length(var.fargate_addon_namespaces) > 0 ? 1 : 0

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${replace(var.name_prefix, "/^eks-/", "")}-addons"
  pod_execution_role_arn = aws_iam_role.fargate[0].arn
  subnet_ids             = var.private_subnet_ids

  dynamic "selector" {
    for_each = var.fargate_addon_namespaces
    content {
      namespace = selector.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-fargate-addons"
  }

  # EKS no permite crear profiles en paralelo.
  depends_on = [aws_eks_fargate_profile.workload]
}

## -----------------------------------------------------
## OIDC Provider (for IRSA)
## -----------------------------------------------------

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.name_prefix}-eks-oidc"
  }
}

## -----------------------------------------------------
## EKS Add-ons (VPC CNI, CoreDNS, kube-proxy)
## -----------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version

  # En Fargate: habilitar Network Policy Controller nativo del VPC CNI
  # Reemplaza a Calico que no puede correr como DaemonSet en Fargate
  configuration_values = var.enable_fargate ? jsonencode({
    enableNetworkPolicy = "true"
  }) : null

  tags = {
    Name = "${var.name_prefix}-vpc-cni"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  addon_version               = data.aws_eks_addon_version.coredns.version

  # En Fargate: computeType=Fargate reemplaza la annotation por defecto
  # (eks.amazonaws.com/compute-type: ec2) que dejaría CoreDNS en Pending
  # al no haber nodos EC2. Nativo del addon, sin kubectl patch.
  configuration_values = var.enable_fargate ? jsonencode({
    computeType  = "Fargate"
    replicaCount = 2
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "200m", memory = "256Mi" }
    }
  }) : null

  # Espera a que exista capacidad de cómputo (nodos EC2 o profile de sistema).
  depends_on = [
    aws_eks_node_group.main,
    aws_eks_fargate_profile.system,
  ]

  tags = {
    Name = "${var.name_prefix}-coredns"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version

  tags = {
    Name = "${var.name_prefix}-kube-proxy"
  }
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

## -----------------------------------------------------
## EBS CSI Driver (required for PVCs — Prometheus, Grafana)
## -----------------------------------------------------

# EBS no se adjunta a pods Fargate → solo en modos ec2_*. En Fargate
# la persistencia se hace con EFS CSI (aws-efs-csi-driver).
moved {
  from = aws_eks_addon.ebs_csi
  to   = aws_eks_addon.ebs_csi[0]
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ec2_nodes ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = aws_iam_role.ebs_csi.arn

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "${var.name_prefix}-ebs-csi"
  }
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = true
}
