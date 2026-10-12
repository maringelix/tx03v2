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
      "2147483647" = "allow"
    }
    error_message = "Exactly two deny rules and the default allow (no rate limit that could block the smoke test)."
  }

  assert {
    condition = toset(flatten([
      for r in google_compute_security_policy.this[0].rule : [for m in r.match : [for e in m.expr : e.expression]] if r.priority < 2000
      ])) == toset([
      "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})",
      "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})",
    ])
    error_message = "Preconfigured rules sqli-v33-stable and xss-v33-stable at sensitivity 1."
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
    project_id             = "tx03v2-lab-example"
    deploy_service_account = "dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com"
    enable_waf             = false
  }

  assert {
    condition     = local.contract_keys["waf/security-policy"] == "none"
    error_message = "enable_waf = false must publish waf/security-policy = none (dx03v2 then deploys without GCPBackendPolicies)."
  }
}
