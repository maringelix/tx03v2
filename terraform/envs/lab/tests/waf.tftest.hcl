# Cloud Armor policy of the contract (enable_waf = true, the default) and the literal none without
# it. modules/waf tested directly, plus the root wiring of enable_waf.

mock_provider "google" {
  source = "../../tests/mocks"
}

run "waf_policy_follows_the_contract" {
  command = apply

  module {
    source = "../../modules/waf"
  }

  variables {
    name       = "tx03v2-lab"
    enable_waf = true
  }

  assert {
    condition = (
      length(google_compute_security_policy.this) == 1 &&
      google_compute_security_policy.this[0].name == "tx03v2-lab-waf" &&
      google_compute_security_policy.this[0].type == "CLOUD_ARMOR" &&
      output.security_policy_name == "tx03v2-lab-waf"
    )
    error_message = "Backend security policy tx03v2-lab-waf (Cloud Armor Standard)."
  }

  assert {
    condition = (
      google_compute_security_policy.this[0].advanced_options_config[0].request_body_inspection_size == "64KB" &&
      google_compute_security_policy.this[0].advanced_options_config[0].json_parsing == "STANDARD"
    )
    error_message = "The first 64 KB of each body are inspected (the 70 KB smoke body still reaches the API), JSON parsed field by field."
  }

  assert {
    condition = { for r in google_compute_security_policy.this[0].rule : tostring(r.priority) => r.action } == {
      "1000"       = "deny(403)"
      "1001"       = "deny(403)"
      "1002"       = "deny(403)"
      "1003"       = "deny(403)"
      "1004"       = "deny(403)"
      "1005"       = "deny(403)"
      "1006"       = "deny(403)"
      "1900"       = "throttle"
      "2147483647" = "allow"
    }
    error_message = "Seven CRS categories, a 600/minute/IP throttle and the default allow."
  }

  assert {
    condition = toset(flatten([
      for r in google_compute_security_policy.this[0].rule : [for m in r.match : [for e in m.expr : e.expression]] if r.priority < 2000
      ])) == toset([
      "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('methodenforcement-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 1})",
    ])
    error_message = "Seven preconfigured CRS 3.3 rule groups at sensitivity 1."
  }

  assert {
    condition = (
      one([for r in google_compute_security_policy.this[0].rule : r if r.priority == 1900]).rate_limit_options[0].rate_limit_threshold[0].count == 600 &&
      google_compute_security_policy.this[0].adaptive_protection_config[0].layer_7_ddos_defense_config[0].enable
    )
    error_message = "Per-IP limit must stay above the smoke contract and Adaptive Protection detection must be on."
  }
}

run "no_waf_publishes_none" {
  command = apply

  module {
    source = "../../modules/waf"
  }

  variables {
    name       = "tx03v2-lab"
    enable_waf = false
  }

  assert {
    condition     = length(google_compute_security_policy.this) == 0 && output.security_policy_name == "none" && output.security_policy_id == null
    error_message = "Without the WAF there is no policy and the contract key waf/security-policy is the literal none."
  }
}

run "root_wiring_of_enable_waf" {
  command = plan

  variables {
    github_owner           = "maringelix"
    project_id             = "tx03v2-lab-example"
    deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    enable_waf             = false
  }

  assert {
    condition     = local.contract_keys["waf/security-policy"] == "none"
    error_message = "enable_waf = false must publish waf/security-policy = none (dx03v2 then deploys without GCPBackendPolicies)."
  }
}
