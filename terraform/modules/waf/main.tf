# Cloud Armor backend security policy of the lab (contract: tx03v2-lab-waf, Standard tier,
# global), attached by dx03v2 to its Services through GCPBackendPolicy (securityPolicy).
# Preconfigured WAF rules sqli-v33-stable and xss-v33-stable at sensitivity 1 deny with 403; the
# default rule allows. The first 64 KB of every body are inspected (the maximum); larger bodies are
# not blocked for their size, so the 70 KB body of the dx03v2 smoke test reaches the API, which
# answers 413 itself. Standard JSON parsing lets the WAF read JSON bodies field by field.
# No rule may block the smoke test; a rate limit, if ever added, must be >= 300 requests per minute
# per client (contract).
resource "google_compute_security_policy" "this" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.name}-waf"
  description = "WAF of the ${var.name} Gateway (preconfigured SQLi and XSS rules)."
  type        = "CLOUD_ARMOR"

  advanced_options_config {
    json_parsing                 = "STANDARD"
    request_body_inspection_size = "64KB"
    log_level                    = "NORMAL"
  }

  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "OWASP SQL injection (sqli-v33-stable, sensitivity 1)"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1001
    description = "OWASP cross-site scripting (xss-v33-stable, sensitivity 1)"
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default rule: allow everything the WAF rules above did not deny."
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
