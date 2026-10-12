output "security_policy_name" {
  description = "Cloud Armor policy name, or the literal none without WAF (contract key waf/security-policy)."
  value       = var.enable_waf ? google_compute_security_policy.this[0].name : "none"
}

output "security_policy_id" {
  description = "Cloud Armor policy ID, or null without WAF."
  value       = var.enable_waf ? google_compute_security_policy.this[0].id : null
}
