output "argocd_namespace" {
  description = "Namespace donde se instaló ArgoCD."
  value       = var.enable_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : ""
}

output "argocd_release_status" {
  description = "Status del Helm release de ArgoCD."
  value       = var.enable_argocd ? helm_release.argocd[0].status : ""
}

output "cilium_release_status" {
  description = "Status del Helm release de Cilium."
  value       = var.enable_cilium ? helm_release.cilium[0].status : ""
}

output "network_policy_engine" {
  description = "Engine de NetworkPolicy activo."
  value       = var.enable_cilium ? "cilium" : "none"
}

output "gateway_api_controller" {
  description = "Controller de Gateway API activo."
  value       = var.enable_cilium ? "cilium" : "none"
}

output "cilium_ready" {
  description = "Marker que indica que Cilium está desplegado. Usar como depends_on para addons que requieren networking."
  value       = var.enable_cilium

  depends_on = [helm_release.cilium]
}
