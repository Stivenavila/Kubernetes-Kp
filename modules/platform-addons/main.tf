## =============================================================
## Platform Add-ons: Metrics Server, VPA, External-DNS,
##                   Cert-Manager, Falco, Prometheus, Grafana
## =============================================================
##
## Lógica de escalado por compute mode:
## ┌──────────────┬──────────────────────────────────────────┐
## │ EC2 Mode     │ Karpenter (nodos) + VPA (pods) + HPA    │
## │ Fargate Mode │ HPA (replicas) + VPA (requests/limits)  │
## │              │ Karpenter DESHABILITADO                  │
## │              │ Falco DESHABILITADO (no kernel access)   │
## └──────────────┴──────────────────────────────────────────┘
## =============================================================

## -----------------------------------------------------
## Metrics Server (requerido para HPA — crítico en Fargate)
## En Fargate, HPA es el ÚNICO mecanismo de escalado horizontal.
## En EC2 mode también es útil para HPA a nivel pod.
## -----------------------------------------------------

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      replicas = var.ha_enabled ? 2 : 1
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
      metrics = {
        enabled = true
      }
    })
  ]
}

## -----------------------------------------------------
## VPA — Vertical Pod Autoscaler
## Funciona tanto en EC2 como en Fargate.
## En Fargate: ajusta requests/limits → AWS re-provisions el pod
## con el tamaño correcto de vCPU/memory.
## -----------------------------------------------------

resource "helm_release" "vpa" {
  count = var.enable_vpa ? 1 : 0

  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = var.vpa_chart_version
  namespace  = "kube-system"

  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      recommender = {
        enabled = true
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
      updater = {
        enabled = true
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
      admissionController = {
        enabled = true
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
    })
  ]
}

## -----------------------------------------------------
## External-DNS
## -----------------------------------------------------

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  timeout         = 600
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      provider = {
        name = "aws"
      }
      env = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        }
      ]
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
        }
      }
      domainFilters = var.domain_filters
      policy        = "sync"
      registry      = "txt"
      txtOwnerId    = var.cluster_name
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "100m", memory = "128Mi" }
      }
    })
  ]
}

## -----------------------------------------------------
## Cert-Manager
## -----------------------------------------------------

resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  namespace  = "kube-system"

  timeout         = 900
  atomic          = false
  cleanup_on_fail = false

  ## Limpia CRDs de cert-manager al destruir (resource-policy:keep los deja huérfanos)
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete crd \
        certificaterequests.cert-manager.io certificates.cert-manager.io \
        challenges.acme.cert-manager.io clusterissuers.cert-manager.io \
        issuers.cert-manager.io orders.acme.cert-manager.io \
        --ignore-not-found=true 2>/dev/null || true
    EOT
  }

  values = [
    yamlencode(merge(
      {
        crds = {
          enabled = true
          keep    = false
        }
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager[0].arn
          }
        }
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
        prometheus = {
          enabled = true
          servicemonitor = {
            enabled = false
          }
        }
      },
      # Fargate no soporta fsGroup arbitrario — solo se aplica en EC2
      var.enable_fargate ? {} : {
        securityContext = {
          fsGroup = 1001
        }
      }
    ))
  ]
}

## ClusterIssuer for Let's Encrypt (staging + prod)
## Se usa kubectl_manifest para evitar bloqueos por finalizers en destroy.
resource "kubectl_manifest" "letsencrypt_staging" {
  count = var.enable_cert_manager && var.letsencrypt_email != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-staging-key"
        }
        solvers = [{
          dns01 = {
            route53 = {
              region = var.aws_region
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "letsencrypt_prod" {
  count = var.enable_cert_manager && var.letsencrypt_email != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [{
          dns01 = {
            route53 = {
              region = var.aws_region
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

## -----------------------------------------------------
## StorageClass gp3 (si no existe)
## -----------------------------------------------------

resource "kubernetes_storage_class" "gp3" {
  count = var.enable_storage_class_gp3 ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.amazonaws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}
