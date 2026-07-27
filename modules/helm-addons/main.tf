## -----------------------------------------------------
## Namespace: ArgoCD
## -----------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  timeouts {
    delete = "5m"
  }
}

## -----------------------------------------------------
## ArgoCD — Helm Release
## Depende de Cilium para garantizar que la CNI/network policy
## esté operativa antes de desplegar pods de ArgoCD.
## -----------------------------------------------------

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name

  timeout         = 900
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true

  depends_on = [helm_release.cilium]

  ## Evita que queden CRDs huérfanos en destroy
  ## El chart de ArgoCD usa resource-policy:keep por defecto en sus CRDs.
  ## Con postrender o set podemos sobreescribir, pero la forma más limpia
  ## es un provisioner que limpia los CRDs al destruir.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
        --ignore-not-found=true 2>/dev/null || true
    EOT
  }

  values = [
    yamlencode({
      global = {
        domain = ""
      }
      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
          }
        }
        extraArgs = ["--insecure"]
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        secret = var.argocd_admin_password != "" ? {
          argocdServerAdminPassword = var.argocd_admin_password
        } : {}
      }
      controller = {
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "1000m", memory = "1Gi" }
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      dex = {
        enabled = false
      }
      notifications = {
        enabled = false
      }
      applicationSet = {
        enabled = true
      }
      redis = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
      }
      ha = {
        enabled = var.ha_enabled
      }
    })
  ]
}

## -----------------------------------------------------
## Cilium — CNI + Network Policy + Gateway API + Hubble
## Reemplaza Calico. Cilium actúa como:
##   - Network Policy engine (L3/L4/L7)
##   - Gateway API controller (GatewayClass, HTTPRoute, etc.)
##   - Observabilidad con Hubble UI
## -----------------------------------------------------

resource "helm_release" "cilium" {
  count = var.enable_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"

  timeout         = 900
  atomic          = false
  cleanup_on_fail = false
  replace         = true
  force_update    = true
  wait            = true

  values = [
    yamlencode({
      # EKS integration — preserve VPC CNI for pod networking
      cni = {
        chainingMode = "aws-cni"
        exclusive    = false
      }
      enableIPv4Masquerade = false
      routingMode          = "native"
      endpointRoutes = {
        enabled = true
      }

      # Node init for EKS
      nodeinit = {
        enabled = true
      }

      # Gateway API
      gatewayAPI = {
        enabled = true
      }

      # Hubble — observabilidad
      hubble = {
        enabled = true
        relay = {
          enabled = true
        }
        ui = {
          enabled = true
          service = {
            type = "LoadBalancer"
            annotations = {
              "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
              "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            }
          }
        }
      }

      # Operator
      operator = {
        replicas = var.ha_enabled ? 2 : 1
      }

      # Resources
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    })
  ]
}
