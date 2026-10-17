# Cloud Armor backend security policy of the lab (contract: tx03v2-lab-waf, Standard tier,
# global), attached by dx03v2 to its Services through GCPBackendPolicy (securityPolicy).
# Seven CRS 3.3 categories at sensitivity 1 deny with 403. The 600/minute/IP throttle remains
# above the app smoke load (contract minimum 300/minute). Adaptive Protection on Standard produces
# basic detection alerts, not Enterprise signatures or automatic mitigation. The first 64 KB of a
# body are inspected; the API itself rejects the smoke's 70 KB body with 413.
locals {
  waf_categories = {
    1000 = "sqli"
    1001 = "xss"
    1002 = "lfi"
    1003 = "rfi"
    1004 = "rce"
    1005 = "methodenforcement"
    1006 = "scannerdetection"
  }
}

resource "google_compute_security_policy" "this" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.name}-waf"
  description = "WAF of the ${var.name} Gateway (seven CRS categories, IP throttle and basic Adaptive Protection alerts)."
  type        = "CLOUD_ARMOR"

  advanced_options_config {
    json_parsing                 = "STANDARD"
    request_body_inspection_size = "64KB"
    log_level                    = "NORMAL"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }

  dynamic "rule" {
    for_each = local.waf_categories
    content {
      action      = "deny(403)"
      priority    = tonumber(rule.key)
      description = "OWASP CRS ${rule.value} (v33 stable, sensitivity 1)"
      match {
        expr {
          expression = "evaluatePreconfiguredWaf('${rule.value}-v33-stable', {'sensitivity': 1})"
        }
      }
    }
  }

  rule {
    action      = "throttle"
    priority    = 1900
    description = "Per-client IP burst limit, 600 requests per minute (above the app smoke contract)."
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 600
        interval_sec = 60
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
