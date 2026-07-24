output "argocd_namespace" {
  description = "Namespace donde se instaló ArgoCD."
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_release_status" {
  description = "Status del Helm release de ArgoCD."
  value       = helm_release.argocd.status
}

output "cilium_release_status" {
  description = "Status del Helm release de Cilium."
  value       = helm_release.cilium.status
}

output "network_policy_engine" {
  description = "Engine de NetworkPolicy activo."
  value       = "cilium"
}

output "gateway_api_controller" {
  description = "Controller de Gateway API activo."
  value       = "cilium"
}
